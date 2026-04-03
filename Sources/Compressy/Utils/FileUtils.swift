import Foundation
import UniformTypeIdentifiers

enum FileUtils {
    static let supported_video_types: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv"
    ]

    static let supported_image_types: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif", "bmp"
    ]

    static func detect_file_type(url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        if supported_video_types.contains(ext) { return .video }
        return .image
    }

    static func is_supported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supported_video_types.contains(ext) || supported_image_types.contains(ext)
    }

    static func file_size(url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }

    static func format_size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
