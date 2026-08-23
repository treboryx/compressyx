import AppKit
import Foundation

enum FileType: String, Sendable {
    case video
    case image
}

enum CompressionStatus: String, Sendable {
    case pending
    case compressing
    case completed
    case failed
    case cancelled
}

@Observable
@MainActor
final class CompressionItem: Identifiable {
    let id = UUID()
    let url: URL
    let file_name: String
    let file_type: FileType
    let original_size: Int64

    var compressed_size: Int64?
    var status: CompressionStatus = .pending
    var progress: Double = 0.0
    var error_message: String?
    var output_url: URL?
    var thumbnail: NSImage?

    /// The running ffmpeg/pngquant process, stored so we can kill it on cancel
    var active_process: Process?

    var is_cancellable: Bool {
        status == .compressing || status == .pending
    }

    var is_retryable: Bool {
        status == .failed || status == .cancelled
    }

    var savings_percentage: Double? {
        guard let compressed = compressed_size, original_size > 0 else { return nil }
        return (1.0 - Double(compressed) / Double(original_size)) * 100.0
    }

    init(url: URL) {
        self.url = url
        self.file_name = url.lastPathComponent
        self.file_type = FileUtils.detect_file_type(url: url)
        self.original_size = FileUtils.file_size(url: url)
    }

    func cancel() {
        guard is_cancellable else { return }
        active_process?.terminate()
        active_process = nil
        status = .cancelled
        progress = 0.0
        // Clean up partial output
        if let output = output_url {
            try? FileManager.default.removeItem(at: output)
            output_url = nil
        }
    }

    func reset_for_retry() {
        guard is_retryable else { return }
        status = .pending
        progress = 0.0
        error_message = nil
        compressed_size = nil
        output_url = nil
        active_process = nil
    }
}
