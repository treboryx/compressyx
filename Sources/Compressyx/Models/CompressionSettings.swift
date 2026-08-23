import Foundation

enum VideoCodec: String, CaseIterable, Sendable {
    case h264 = "H.264"
    case h265 = "H.265 (HEVC)"

    var ffmpeg_encoder: String {
        switch self {
        case .h264: return "h264_videotoolbox"
        case .h265: return "hevc_videotoolbox"
        }
    }
}

enum VideoOutputFormat: String, CaseIterable, Sendable {
    case same_as_input = "Same as input"
    case mp4 = "MP4"
    case mov = "MOV"
    case mkv = "MKV"
    case webm = "WebM"

    var file_extension: String? {
        switch self {
        case .same_as_input: return nil
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .mkv: return "mkv"
        case .webm: return "webm"
        }
    }

    var requires_software_encoder: Bool {
        self == .webm
    }

    var ffmpeg_encoder_override: String? {
        switch self {
        case .webm: return "libvpx-vp9"
        default: return nil
        }
    }
}

enum ImageOutputFormat: String, CaseIterable, Sendable {
    case same_as_input = "Same as input"
    case jpeg = "JPEG"
    case png = "PNG"
    case heic = "HEIC"
    case webp = "WebP"

    var file_extension: String? {
        switch self {
        case .same_as_input: return nil
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .webp: return "webp"
        }
    }
}

enum QualityPreset: String, CaseIterable, Sendable {
    case highest = "Highest"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var videotoolbox_quality: Int {
        switch self {
        case .highest: return 35
        case .high: return 50
        case .medium: return 65
        case .low: return 80
        }
    }

    var crf: Int {
        switch self {
        case .highest: return 18
        case .high: return 23
        case .medium: return 28
        case .low: return 35
        }
    }

    var image_quality: Double {
        switch self {
        case .highest: return 1.0
        case .high: return 0.85
        case .medium: return 0.7
        case .low: return 0.5
        }
    }

    var pngquant_range: String {
        switch self {
        case .highest: return "90-100"
        case .high: return "70-95"
        case .medium: return "50-80"
        case .low: return "30-60"
        }
    }
}

enum OutputFolderOption: String, CaseIterable, Sendable {
    case same_as_input = "Same as input"
    case custom = "Custom..."
}

@Observable
@MainActor
final class CompressionSettings {
    static let shared = CompressionSettings()

    var video_codec: VideoCodec = .h265
    var quality_preset: QualityPreset = .high
    var video_output_format: VideoOutputFormat = .same_as_input
    var image_output_format: ImageOutputFormat = .same_as_input
    var output_directory: URL?
    var remove_input_file: Bool = false
    var max_concurrent: Int = 3

    var output_folder_option: OutputFolderOption {
        get { output_directory == nil ? .same_as_input : .custom }
        set {
            if newValue == .same_as_input {
                output_directory = nil
            }
        }
    }

    func output_url(for source: URL, file_type: FileType) -> URL {
        let base_name = source.deletingPathExtension().lastPathComponent
        let ext: String
        switch file_type {
        case .video:
            ext = video_output_format.file_extension ?? source.pathExtension
        case .image:
            ext = image_output_format.file_extension ?? source.pathExtension
        }
        let dir = output_directory ?? source.deletingLastPathComponent()
        return dir.appendingPathComponent("\(base_name)_compressed.\(ext)")
    }
}
