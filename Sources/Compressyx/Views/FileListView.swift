import SwiftUI

struct FileListView: View {
    var queue: CompressionQueue
    var settings: CompressionSettings

    var body: some View {
        List {
            ForEach(queue.items) { item in
                FileRowView(item: item)
                    .contextMenu {
                        if item.status == .compressing {
                            Button("Cancel") {
                                item.cancel()
                            }
                        }

                        if item.is_retryable {
                            Button("Retry") {
                                item.reset_for_retry()
                                queue.compress_all(settings: settings)
                            }
                        }

                        if let output = item.output_url, item.status == .completed {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([output])
                            }
                        }

                        Button("Show Original in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }

                        Divider()

                        Button("Remove", role: .destructive) {
                            queue.remove_item(item)
                        }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}
