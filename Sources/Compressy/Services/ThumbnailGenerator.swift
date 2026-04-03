import AppKit
import AVFoundation
import Foundation

enum ThumbnailGenerator {
    static let thumbnail_size = NSSize(width: 48, height: 48)

    static func generate(for url: URL, type: FileType) async -> NSImage? {
        switch type {
        case .video:
            return await generate_video_thumbnail(url: url)
        case .image:
            return generate_image_thumbnail(url: url)
        }
    }

    private static func generate_video_thumbnail(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnail_size.width * 2, height: thumbnail_size.height * 2)

        do {
            let (image, _) = try await generator.image(at: .zero)
            let ns_image = NSImage(cgImage: image, size: thumbnail_size)
            return ns_image
        } catch {
            return nil
        }
    }

    private static func generate_image_thumbnail(url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let resized = NSImage(size: thumbnail_size)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: thumbnail_size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        return resized
    }
}
