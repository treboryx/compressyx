import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: CompressionSettings
    var is_locked: Bool = false

    @State private var ffmpeg_installed = VideoCompressor.find_ffmpeg() != nil
    @State private var pngquant_installed = ImageCompressor.find_pngquant() != nil
    @State private var cwebp_installed = ImageCompressor.find_cwebp() != nil
    @State private var installing: Set<String> = []
    @State private var install_error: String?

    private var missing_packages: [String] {
        var packages: [String] = []
        if !ffmpeg_installed { packages.append("ffmpeg") }
        if !pngquant_installed { packages.append("pngquant") }
        if !cwebp_installed { packages.append("webp") }
        return packages
    }

    private var homebrew_installed: Bool {
        Dependencies.find_brew() != nil
    }

    var body: some View {
        TabView {
            general_tab
                .tabItem { Label("General", systemImage: "gearshape") }

            shortcuts_tab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            dependencies_tab
                .tabItem { Label("Dependencies", systemImage: "shippingbox") }
        }
        .frame(width: 450, height: 350)
    }

    // MARK: - General Tab

    private var general_tab: some View {
        Form {
            Section("Video") {
                Picker("Codec", selection: $settings.video_codec) {
                    ForEach(VideoCodec.allCases, id: \.self) { codec in
                        Text(codec.rawValue).tag(codec)
                    }
                }

                Picker("Output format", selection: $settings.video_output_format) {
                    ForEach(VideoOutputFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
            }

            Section("Image") {
                Picker("Output format", selection: $settings.image_output_format) {
                    ForEach(ImageOutputFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
            }

            Section("Quality") {
                Picker("Quality", selection: $settings.quality_preset) {
                    ForEach(QualityPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
            }

            Section("Output") {
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

                if let dir = settings.output_directory {
                    HStack {
                        Text(dir.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Change") {
                            choose_output_directory()
                        }
                        .font(.caption)
                    }
                }

                Toggle("Remove input file", isOn: $settings.remove_input_file)
            }

            Section("Performance") {
                Stepper("Parallel tasks: \(settings.max_concurrent)", value: $settings.max_concurrent, in: 1...8)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Shortcuts Tab

    private var shortcuts_tab: some View {
        Form {
            Section("Keyboard Shortcuts") {
                HStack {
                    Text("Add Files")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .add_files)
                }
                HStack {
                    Text("Compress All")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .compress_all)
                }
                HStack {
                    Text("Cancel")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .cancel_compression)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Dependencies Tab

    private var dependencies_tab: some View {
        Form {
            Section("Required Tools") {
                dependency_row(
                    name: "FFmpeg",
                    purpose: "Video compression",
                    is_installed: ffmpeg_installed,
                    is_installing: installing.contains("ffmpeg"),
                    path: VideoCompressor.find_ffmpeg()?.path,
                    install_action: { install(["ffmpeg"]) }
                )

                dependency_row(
                    name: "pngquant",
                    purpose: "PNG compression",
                    is_installed: pngquant_installed,
                    is_installing: installing.contains("pngquant"),
                    path: ImageCompressor.find_pngquant()?.path,
                    install_action: { install(["pngquant"]) }
                )

                dependency_row(
                    name: "cwebp",
                    purpose: "WebP compression",
                    is_installed: cwebp_installed,
                    is_installing: installing.contains("webp"),
                    path: ImageCompressor.find_cwebp()?.path,
                    install_action: { install(["webp"]) }
                )

                if let error = install_error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !missing_packages.isEmpty {
                Section {
                    if homebrew_installed {
                        Button {
                            install(missing_packages)
                        } label: {
                            if installing.isEmpty {
                                Label(
                                    "Install All Missing (\(missing_packages.count))",
                                    systemImage: "arrow.down.circle.fill"
                                )
                            } else {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Installing \(installing.sorted().joined(separator: ", "))...")
                                }
                            }
                        }
                        .disabled(!installing.isEmpty)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Homebrew is required", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Compressyx installs these tools with Homebrew. Install it first, then come back.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("Get Homebrew", destination: URL(string: Dependencies.homebrew_url)!)
                                .font(.caption)
                        }
                    }
                }
            }

            Section {
                if missing_packages.isEmpty {
                    Label("All tools installed", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Text("Compressyx works without these, but each unlocks a format: FFmpeg for video, pngquant for PNG, cwebp for WebP.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh_installed)
    }

    // MARK: - Dependency Row

    @ViewBuilder
    private func dependency_row(
        name: String,
        purpose: String,
        is_installed: Bool,
        is_installing: Bool,
        path: String?,
        install_action: @escaping () -> Void
    ) -> some View {
        if is_installed {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("\(name)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text(purpose)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let path {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack {
                Label("\(name)", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)

                Spacer()

                if is_installing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Install") {
                        install_action()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh_installed() {
        ffmpeg_installed = VideoCompressor.find_ffmpeg() != nil
        pngquant_installed = ImageCompressor.find_pngquant() != nil
        cwebp_installed = ImageCompressor.find_cwebp() != nil
    }

    private func install(_ packages: [String]) {
        guard installing.isEmpty else { return }
        installing = Set(packages)
        install_error = nil

        Task {
            let success = await Dependencies.install(packages)
            installing = []
            refresh_installed()

            if !success && !missing_packages.isEmpty {
                let still_missing = missing_packages.joined(separator: " ")
                install_error = "Install failed. Run 'brew install \(still_missing)' in Terminal."
            }
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
}
