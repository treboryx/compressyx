import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: CompressionSettings
    var is_locked: Bool = false

    @State private var ffmpeg_installed = VideoCompressor.find_ffmpeg() != nil
    @State private var pngquant_installed = ImageCompressor.find_pngquant() != nil
    @State private var installing_ffmpeg = false
    @State private var installing_pngquant = false
    @State private var install_error: String?

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
                    is_installing: installing_ffmpeg,
                    path: VideoCompressor.find_ffmpeg()?.path,
                    install_action: install_ffmpeg
                )

                dependency_row(
                    name: "pngquant",
                    purpose: "PNG compression",
                    is_installed: pngquant_installed,
                    is_installing: installing_pngquant,
                    path: ImageCompressor.find_pngquant()?.path,
                    install_action: install_pngquant
                )

                if let error = install_error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Dependencies are installed via Homebrew. If you don't have Homebrew, visit https://brew.sh")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
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

    private func install_ffmpeg() {
        installing_ffmpeg = true
        install_error = nil
        run_brew_install("ffmpeg") { success in
            installing_ffmpeg = false
            ffmpeg_installed = VideoCompressor.find_ffmpeg() != nil
            if !success && !ffmpeg_installed {
                install_error = "Failed to install FFmpeg. Run 'brew install ffmpeg' manually."
            }
        }
    }

    private func install_pngquant() {
        installing_pngquant = true
        install_error = nil
        run_brew_install("pngquant") { success in
            installing_pngquant = false
            pngquant_installed = ImageCompressor.find_pngquant() != nil
            if !success && !pngquant_installed {
                install_error = "Failed to install pngquant. Run 'brew install pngquant' manually."
            }
        }
    }

    private func run_brew_install(_ package: String, completion: @escaping @Sendable (Bool) -> Void) {
        let brew_paths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        guard let brew_path = brew_paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            install_error = "Homebrew not found. Install from https://brew.sh"
            installing_ffmpeg = false
            installing_pngquant = false
            return
        }

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew_path)
            process.arguments = ["install", package]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                let success = process.terminationStatus == 0
                Task { @MainActor in
                    completion(success)
                }
            } catch {
                Task { @MainActor in
                    completion(false)
                }
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
