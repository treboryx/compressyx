import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var queue: CompressionQueue
    var compact: Bool = false

    @State private var is_hovering = false

    var body: some View {
        VStack(spacing: compact ? 4 : 16) {
            if !compact {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }

            Text(compact ? "Drop more files or folders here" : "Drop videos, images, or folders here")
                .font(compact ? .caption : .title3)
                .foregroundStyle(.secondary)

            if !compact {
                Text("Supports MP4, MOV, MKV, JPG, PNG, HEIC, WebP")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(
            is_hovering ? .regular.tint(.accentColor) : .regular,
            in: .rect(cornerRadius: compact ? 12 : 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 12 : 22)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(is_hovering ? Color.accentColor : Color.secondary.opacity(0.25))
        }
        .animation(.smooth(duration: 0.25), value: is_hovering)
        .padding(compact ? 10 : 20)
        .onDrop(of: [.fileURL], isTargeted: $is_hovering) { providers in
            handle_drop(providers)
            return true
        }
    }

    private func handle_drop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadTransferable(type: URL.self) { result in
                guard case .success(let url) = result else { return }

                // Runs off the main actor deliberately: enumerating a deep tree can be slow.
                let expanded = FileUtils.expand(urls: [url])
                guard !expanded.isEmpty else { return }

                Task { @MainActor in
                    queue.add_files(expanded)
                }
            }
        }
    }
}
