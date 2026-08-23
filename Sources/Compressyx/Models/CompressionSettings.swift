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

    private enum Key {
        static let video_codec = "settings.video_codec"
        static let quality_preset = "settings.quality_preset"
        static let video_output_format = "settings.video_output_format"
        static let image_output_format = "settings.image_output_format"
        static let output_directory = "settings.output_directory"
        static let remove_input_file = "settings.remove_input_file"
        static let max_concurrent = "settings.max_concurrent"
    }

    var video_codec: VideoCodec = .h265 {
        didSet { UserDefaults.standard.set(video_codec.rawValue, forKey: Key.video_codec) }
    }

    var quality_preset: QualityPreset = .high {
        didSet { UserDefaults.standard.set(quality_preset.rawValue, forKey: Key.quality_preset) }
    }

    var video_output_format: VideoOutputFormat = .same_as_input {
        didSet { UserDefaults.standard.set(video_output_format.rawValue, forKey: Key.video_output_format) }
    }

    var image_output_format: ImageOutputFormat = .same_as_input {
        didSet { UserDefaults.standard.set(image_output_format.rawValue, forKey: Key.image_output_format) }
    }

    var output_directory: URL? {
        didSet {
            if let path = output_directory?.path {
                UserDefaults.standard.set(path, forKey: Key.output_directory)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.output_directory)
            }
        }
    }

    var remove_input_file: Bool = false {
        didSet { UserDefaults.standard.set(remove_input_file, forKey: Key.remove_input_file) }
    }

    var max_concurrent: Int = 3 {
        didSet { UserDefaults.standard.set(max_concurrent, forKey: Key.max_concurrent) }
    }

    private init() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: Key.video_codec), let value = VideoCodec(rawValue: raw) {
            video_codec = value
        }
        if let raw = defaults.string(forKey: Key.quality_preset), let value = QualityPreset(rawValue: raw) {
            quality_preset = value
        }
        if let raw = defaults.string(forKey: Key.video_output_format), let value = VideoOutputFormat(rawValue: raw) {
            video_output_format = value
        }
        if let raw = defaults.string(forKey: Key.image_output_format), let value = ImageOutputFormat(rawValue: raw) {
            image_output_format = value
        }
        if let path = defaults.string(forKey: Key.output_directory) {
            output_directory = URL(fileURLWithPath: path)
        }

        remove_input_file = defaults.bool(forKey: Key.remove_input_file)

        let stored_concurrent = defaults.integer(forKey: Key.max_concurrent)
        if stored_concurrent > 0 {
            max_concurrent = stored_concurrent
        }
    }

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
            ext = image_output_format.file_extension ?? FileUtils.same_as_input_extension(for: source)
        }
        let dir = output_directory ?? source.deletingLastPathComponent()
        return dir.appendingPathComponent("\(base_name)_compressed.\(ext)")
    }
}
