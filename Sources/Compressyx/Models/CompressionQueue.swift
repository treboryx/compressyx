import DockProgress
import Foundation

@Observable
@MainActor
final class CompressionQueue {
    var items: [CompressionItem] = []
    var is_processing = false

    private var batch_task: Task<Void, Never>?

    var pending_count: Int {
        items.filter { $0.status == .pending }.count
    }

    var completed_count: Int {
        items.filter { $0.status == .completed }.count
    }

    var compressing_count: Int {
        items.filter { $0.status == .compressing }.count
    }

    var has_retryable: Bool {
        items.contains { $0.is_retryable }
    }

    /// Overall progress across all items (0.0 - 1.0)
    var overall_progress: Double {
        let total = items.count
        guard total > 0 else { return 0 }
        let sum = items.reduce(0.0) { acc, item in
            switch item.status {
            case .completed: return acc + 1.0
            case .compressing: return acc + item.progress
            case .failed, .cancelled: return acc + 1.0
            default: return acc
            }
        }
        return sum / Double(total)
    }

    // MARK: - Adding files

    func add_files(_ urls: [URL]) {
        let existing_paths = Set(items.map { $0.url.path })

        for url in urls {
            guard FileUtils.is_supported(url: url) else { continue }
            guard !existing_paths.contains(url.path) else { continue }

            let item = CompressionItem(url: url)
            items.append(item)

            Task {
                item.thumbnail = await ThumbnailGenerator.generate(for: url, type: item.file_type)
            }
        }
    }

    // MARK: - Compression

    func compress_all(settings: CompressionSettings) {
        guard !is_processing else { return }
        is_processing = true
        DockProgress.style = .bar

        let max_concurrent = settings.max_concurrent
        let pending = items.filter { $0.status == .pending }

        batch_task = Task {
            var next_index = 0
            var active: [Task<Void, Never>] = []

            // Launch initial batch
            for _ in 0..<min(max_concurrent, pending.count) {
                let item = pending[next_index]
                next_index += 1
                active.append(launch_compress(item, settings: settings))
            }

            // As each completes, launch the next
            while !active.isEmpty {
                if Task.isCancelled { break }
                let first = active.removeFirst()
                await first.value

                // Skip items that were cancelled/removed while waiting
                while next_index < pending.count && pending[next_index].status != .pending {
                    next_index += 1
                }
                if next_index < pending.count {
                    let item = pending[next_index]
                    next_index += 1
                    active.append(launch_compress(item, settings: settings))
                }
            }

            is_processing = false
            batch_task = nil
            DockProgress.progress = 0
        }
    }

    private func launch_compress(_ item: CompressionItem, settings: CompressionSettings) -> Task<Void, Never> {
        Task {
            await compress_item(item, settings: settings)
            update_dock_progress()
        }
    }

    func cancel_all() {
        batch_task?.cancel()
        batch_task = nil

        for item in items where item.status == .compressing || item.status == .pending {
            item.cancel()
        }

        is_processing = false
        DockProgress.progress = 0
    }

    private func update_dock_progress() {
        DockProgress.progress = overall_progress
    }

    func retry_failed(settings: CompressionSettings) {
        for item in items where item.is_retryable {
            item.reset_for_retry()
        }
        compress_all(settings: settings)
    }

    // MARK: - Item management

    func remove_item(_ item: CompressionItem) {
        if item.status == .compressing {
            item.cancel()
        }
        items.removeAll { $0.id == item.id }

        // If no more compressing items, reset processing state
        if compressing_count == 0 && pending_count == 0 {
            batch_task?.cancel()
            batch_task = nil
            is_processing = false
        }
    }

    func clear_completed() {
        items.removeAll { $0.status == .completed }
    }

    func clear_all() {
        cancel_all()
        items.removeAll()
    }

    // MARK: - Private

    private func compress_item(_ item: CompressionItem, settings: CompressionSettings) async {
        item.status = .compressing
        item.progress = 0.0

        let output_url = settings.output_url(for: item.url, file_type: item.file_type)
        let input_url = item.url

        do {
            let output: URL
            let remove_input = settings.remove_input_file
            switch item.file_type {
            case .video:
                let format = settings.video_output_format
                let encoder = format.ffmpeg_encoder_override ?? settings.video_codec.ffmpeg_encoder
                let use_crf = format.requires_software_encoder
                let params = VideoCompressionParams(
                    encoder: encoder,
                    quality: settings.quality_preset.videotoolbox_quality,
                    is_h265: settings.video_codec == .h265 && !format.requires_software_encoder,
                    output_url: output_url,
                    use_crf: use_crf,
                    crf: settings.quality_preset.crf
                )
                output = try await VideoCompressor.compress(
                    input_url: input_url,
                    params: params,
                    on_progress: { [weak self] progress in
                        Task { @MainActor in
                            item.progress = progress
                            self?.update_dock_progress()
                        }
                    },
                    on_process: { process in
                        Task { @MainActor in
                            item.active_process = process
                        }
                    }
                )
            case .image:
                let params = ImageCompressionParams(
                    quality: settings.quality_preset.image_quality,
                    pngquant_range: settings.quality_preset.pngquant_range,
                    output_url: output_url
                )
                output = try await ImageCompressor.compress(
                    input_url: input_url,
                    params: params,
                    on_process: { process in
                        Task { @MainActor in
                            item.active_process = process
                        }
                    }
                )
            }

            // Item may have been cancelled while we were awaiting
            guard item.status == .compressing else { return }

            item.output_url = output
            item.compressed_size = FileUtils.file_size(url: output)
            item.progress = 1.0
            item.status = .completed
            item.active_process = nil

            if remove_input {
                try? FileManager.default.removeItem(at: input_url)
            }
        } catch {
            guard item.status == .compressing else { return }
            item.error_message = error.localizedDescription
            item.status = .failed
            item.active_process = nil
        }
    }
}
