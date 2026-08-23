import SettingsAccess
import SwiftUI

struct ContentView: View {
    @State private var queue = CompressionQueue()
    @Bindable private var settings = CompressionSettings.shared
    @State private var show_missing_deps_alert = false
    @State private var sidebar_visibility: NavigationSplitViewVisibility = .automatic

    private var missing_deps: [String] {
        var deps: [String] = []
        if VideoCompressor.find_ffmpeg() == nil { deps.append("FFmpeg") }
        if ImageCompressor.find_pngquant() == nil { deps.append("pngquant") }
        if ImageCompressor.find_cwebp() == nil { deps.append("cwebp") }
        return deps
    }

    @State private var ffmpeg_installed = VideoCompressor.find_ffmpeg() != nil
    @State private var pngquant_installed = ImageCompressor.find_pngquant() != nil
    @State private var cwebp_installed = ImageCompressor.find_cwebp() != nil

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebar_visibility) {
            sidebar_view
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            VStack(spacing: 0) {
                toolbar_view
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                if queue.items.isEmpty {
                    DropZoneView(queue: queue)
                } else {
                    VStack(spacing: 0) {
                        FileListView(queue: queue, settings: settings)

                        Divider()

                        DropZoneView(queue: queue, compact: true)
                            .frame(height: 60)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear {
            if !missing_deps.isEmpty {
                show_missing_deps_alert = true
            }
        }
        .alert("Missing Dependencies", isPresented: $show_missing_deps_alert) {
            Button("Open Settings") {
                openSettings()
            }
            Button("OK") {}
        } message: {
            Text("\(missing_deps.joined(separator: " and ")) not found. Install them from Settings (Cmd+,).")
        }
    }

    // MARK: - Sidebar

    private var sidebar_view: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.headline)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Video")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Codec", selection: $settings.video_codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { codec in
                            Text(codec.rawValue).tag(codec)
                        }
                    }
                    .labelsHidden()

                    Picker("Video format", selection: $settings.video_output_format) {
                        ForEach(VideoOutputFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .labelsHidden()

                    DisclosureGroup("Advanced") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resolution")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Resolution", selection: $settings.video_resolution) {
                                ForEach(VideoResolution.allCases, id: \.self) { resolution in
                                    Text(resolution.rawValue).tag(resolution)
                                }
                            }
                            .labelsHidden()

                            Text("Audio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Audio", selection: $settings.audio_handling) {
                                ForEach(AudioHandling.allCases, id: \.self) { handling in
                                    Text(handling.rawValue).tag(handling)
                                }
                            }
                            .labelsHidden()

                            Toggle("Cap frame rate", isOn: Binding(
                                get: { settings.video_fps_cap > 0 },
                                set: { settings.video_fps_cap = $0 ? 30 : 0 }
                            ))
                            .font(.callout)

                            if settings.video_fps_cap > 0 {
                                Stepper("\(settings.video_fps_cap) fps", value: $settings.video_fps_cap, in: 15...60, step: 5)
                                    .font(.callout)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.callout)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Image")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Image format", selection: $settings.image_output_format) {
                        ForEach(ImageOutputFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quality")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Quality", selection: $settings.quality_preset) {
                        ForEach(QualityPreset.allCases, id: \.self) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Output folder", selection: Binding(
                        get: { settings.output_folder_option },
                        set: { new_value in
                            if new_value == .custom {
                                choose_output_directory()
                            } else {
                                settings.output_directory = nil
                            }
                        }
                    )) {
                        ForEach(OutputFolderOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()

                    if let dir = settings.output_directory {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(dir.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Toggle("Remove input file", isOn: $settings.remove_input_file)
                        .font(.callout)

                    Stepper("Parallel: \(settings.max_concurrent)", value: $settings.max_concurrent, in: 1...8)
                        .font(.callout)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Dependencies")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    dep_row(name: "FFmpeg", installed: ffmpeg_installed)
                    dep_row(name: "pngquant", installed: pngquant_installed)
                    dep_row(name: "cwebp", installed: cwebp_installed)

                    if !ffmpeg_installed || !pngquant_installed || !cwebp_installed {
                        Button("Open Settings") {
                            openSettings()
                        }
                        .font(.caption)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(.ultraThinMaterial)
        .onAppear {
            ffmpeg_installed = VideoCompressor.find_ffmpeg() != nil
            pngquant_installed = ImageCompressor.find_pngquant() != nil
            cwebp_installed = ImageCompressor.find_cwebp() != nil
        }
    }

    @ViewBuilder
    private func dep_row(name: String, installed: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(installed ? .green : .red)
                .font(.caption)
            Text(name)
                .font(.callout)
            Spacer()
        }
    }

    private var toolbar_view: some View {
        HStack {
            Button {
                open_file_panel()
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)

            Spacer()

            if !queue.items.isEmpty {
                Text("\(queue.items.count) file\(queue.items.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Spacer()

                if queue.is_processing {
                    Button {
                        queue.cancel_all()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    if queue.has_retryable {
                        Button("Retry Failed") {
                            queue.retry_failed(settings: settings)
                        }
                    }

                    if queue.completed_count > 0 {
                        Button("Clear Done") {
                            queue.clear_completed()
                        }
                    }

                    if queue.items.count > 1 {
                        Button("Clear All") {
                            queue.clear_all()
                        }
                    }

                    Button {
                        queue.compress_all(settings: settings)
                    } label: {
                        Label("Compress All", systemImage: "arrow.down.circle.fill")
                    }
                    .disabled(queue.pending_count == 0)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    private func open_file_panel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .image, .png, .jpeg, .heic, .tiff, .bmp]

        if panel.runModal() == .OK {
            queue.add_files(panel.urls)
        }
    }

    private func choose_output_directory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            settings.output_directory = panel.url
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
