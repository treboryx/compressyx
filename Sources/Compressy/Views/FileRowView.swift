import SwiftUI

struct FileRowView: View {
    var item: CompressionItem

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.file_type == .video ? "film" : "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.file_name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(FileUtils.format_size(item.original_size))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let compressed = item.compressed_size {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(FileUtils.format_size(compressed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let savings = item.savings_percentage {
                        Text("(\(Int(savings))% smaller)")
                            .font(.caption)
                            .foregroundStyle(savings > 0 ? .green : .orange)
                    }
                }
            }

            Spacer()

            // Status
            status_view
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status_view: some View {
        switch item.status {
        case .pending:
            Text("Pending")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .compressing:
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: item.progress)
                        .frame(width: 100)
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    item.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Cancel compression")
            }

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

        case .failed:
            VStack(alignment: .trailing) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                if let error = item.error_message {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .frame(maxWidth: 150)
                }
            }

        case .cancelled:
            Text("Cancelled")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
