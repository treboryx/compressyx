import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageCompressorError: LocalizedError {
    case pngquant_not_found
    case compression_failed(String)
    case unsupported_format(String)
    case image_load_failed
    case cwebp_not_found

    var errorDescription: String? {
        switch self {
        case .pngquant_not_found:
            return "pngquant not found. Install via: brew install pngquant"
        case .compression_failed(let msg):
            return "Image compression failed: \(msg)"
        case .unsupported_format(let ext):
            return "Unsupported format: \(ext)"
        case .image_load_failed:
            return "Could not load image"
        case .cwebp_not_found:
            return "cwebp not found. Install via: brew install webp"
        }
    }
}

struct ImageCompressionParams: Sendable {
    let quality: Double
    let pngquant_range: String
    let output_url: URL
    let target_format: ImageOutputFormat
    let metadata_policy: MetadataPolicy
}

enum ImageCompressor {
    private static func find_tool(_ name: String) -> URL? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func find_pngquant() -> URL? {
        find_tool("pngquant")
    }

    static func find_cwebp() -> URL? {
        find_tool("cwebp")
    }

    /// TIFF and BMP have no ImageOutputFormat case, so they fall back to JPEG.
    private static func resolve_format(input_url: URL, target: ImageOutputFormat) throws -> ImageOutputFormat {
        let ext = input_url.pathExtension.lowercased()
        guard FileUtils.supported_image_types.contains(ext) else {
            throw ImageCompressorError.unsupported_format(ext)
        }
        guard target == .same_as_input else { return target }

        switch ext {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        case "webp": return .webp
        default: return .jpeg
        }
    }

    static func compress(
        input_url: URL,
        params: ImageCompressionParams,
        on_process: @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> URL {
        let format = try resolve_format(input_url: input_url, target: params.target_format)

        switch format {
        case .png:
            try await compress_png(input: input_url, output: params.output_url, pngquant_range: params.pngquant_range, policy: params.metadata_policy, on_process: on_process)
        case .jpeg:
            try encode(input: input_url, output: params.output_url, type: .jpeg,
                       quality: params.quality, policy: params.metadata_policy)
        case .heic:
            try encode(input: input_url, output: params.output_url, type: .heic,
                       quality: params.quality, policy: params.metadata_policy)
        case .webp:
            try await compress_webp(input: input_url, output: params.output_url, quality: params.quality, policy: params.metadata_policy, on_process: on_process)
        case .same_as_input:
            throw ImageCompressorError.unsupported_format(input_url.pathExtension)
        }

        guard FileManager.default.fileExists(atPath: params.output_url.path) else {
            throw ImageCompressorError.compression_failed(
                "Encoder produced no output at \(params.output_url.lastPathComponent)"
            )
        }

        return params.output_url
    }

    /// pngquant only reads PNG, so a non-PNG source is transcoded to a temp PNG first.
    private static func png_source(for input: URL) throws -> (url: URL, is_temporary: Bool) {
        guard input.pathExtension.lowercased() != "png" else { return (input, false) }

        guard let image = NSImage(contentsOf: input),
              let tiff_data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff_data),
              let png_data = bitmap.representation(using: .png, properties: [:])
        else {
            throw ImageCompressorError.image_load_failed
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try png_data.write(to: temp)
        return (temp, true)
    }

    private static func compress_png(input: URL, output: URL, pngquant_range: String, policy: MetadataPolicy, on_process: @escaping @Sendable (Process) -> Void) async throws {
        guard let pngquant = find_pngquant() else {
            throw ImageCompressorError.pngquant_not_found
        }

        let source = try png_source(for: input)
        defer {
            if source.is_temporary {
                try? FileManager.default.removeItem(at: source.url)
            }
        }

        let process = Process()
        process.executableURL = pngquant
        var arguments = ["--quality", pngquant_range, "--force"]
        if policy == .strip_all {
            arguments.append("--strip")
        }
        arguments.append(contentsOf: ["--output", output.path, source.url.path])
        process.arguments = arguments

        let stderr_pipe = Pipe()
        process.standardError = stderr_pipe

        try process.run()
        on_process(process)
        process.waitUntilExit()

        if process.terminationReason == .uncaughtSignal {
            try? FileManager.default.removeItem(at: output)
            throw ImageCompressorError.compression_failed("Cancelled")
        }

        guard process.terminationStatus == 0 || process.terminationStatus == 99 else {
            let error_data = stderr_pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: error_data, encoding: .utf8) ?? "Unknown error"
            throw ImageCompressorError.compression_failed(msg)
        }

        if !FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.copyItem(at: source.url, to: output)
        }
    }

    private static func compress_webp(input: URL, output: URL, quality: Double, policy: MetadataPolicy, on_process: @escaping @Sendable (Process) -> Void) async throws {
        guard let cwebp = find_cwebp() else {
            throw ImageCompressorError.cwebp_not_found
        }

        // Pass readable formats through untouched — transcoding would strip the metadata
        // cwebp is about to copy. Only HEIC and BMP need the PNG bridge.
        // Stripping everything drops the orientation tag with it, and cwebp never rotates
        // pixels, so a portrait photo would come out sideways. The PNG bridge bakes the
        // rotation in, which is exactly what a metadata-free file needs.
        let readable_directly = ["png", "jpg", "jpeg", "tif", "tiff", "webp"]
        let pass_through = policy != .strip_all
            && readable_directly.contains(input.pathExtension.lowercased())
        var source: (url: URL, is_temporary: Bool) =
            pass_through ? (input, false) : try png_source(for: input)

        // cwebp's -metadata is all-or-nothing over EXIF, and GPS lives inside it,
        // so the location has to be gone before cwebp ever sees the file.
        if policy == .strip_location, let stripped = try? gps_stripped_copy(of: source.url) {
            if source.is_temporary {
                try? FileManager.default.removeItem(at: source.url)
            }
            source = (stripped, true)
        }
        defer {
            if source.is_temporary {
                try? FileManager.default.removeItem(at: source.url)
            }
        }

        let process = Process()
        process.executableURL = cwebp
        let metadata: String
        switch policy {
        case .preserve: metadata = "all"
        case .strip_location: metadata = "exif,icc"
        case .strip_all: metadata = "none"
        }

        process.arguments = [
            "-q", "\(Int((quality * 100).rounded()))",
            "-metadata", metadata,
            source.url.path,
            "-o", output.path
        ]

        let stderr_pipe = Pipe()
        process.standardError = stderr_pipe

        try process.run()
        on_process(process)
        process.waitUntilExit()

        if process.terminationReason == .uncaughtSignal {
            try? FileManager.default.removeItem(at: output)
            throw ImageCompressorError.compression_failed("Cancelled")
        }

        guard process.terminationStatus == 0 else {
            let error_data = stderr_pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: error_data, encoding: .utf8) ?? "Unknown error"
            throw ImageCompressorError.compression_failed(msg)
        }
    }

    /// Rewrites the container without re-encoding, so this costs no image quality.
    private static func gps_stripped_copy(of input: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else {
            throw ImageCompressorError.image_load_failed
        }

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(input.pathExtension)

        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else {
            throw ImageCompressorError.compression_failed("Could not create destination for metadata strip")
        }

        // kCFNull removes a key rather than overriding it.
        let overrides = [kCGImagePropertyGPSDictionary: kCFNull] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, overrides)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressorError.compression_failed("Metadata strip failed")
        }
        return temp
    }

    /// Orientation must survive even a full strip, or portrait photos display sideways.
    private static func source_properties(_ source: CGImageSource, policy: MetadataPolicy) -> [CFString: Any] {
        let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        switch policy {
        case .preserve:
            return raw
        case .strip_location:
            var properties = raw
            properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
            return properties
        case .strip_all:
            var properties: [CFString: Any] = [:]
            if let orientation = raw[kCGImagePropertyOrientation] {
                properties[kCGImagePropertyOrientation] = orientation
            }
            return properties
        }
    }

    private static func encode(
        input: URL,
        output: URL,
        type: UTType,
        quality: Double,
        policy: MetadataPolicy
    ) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let cg_image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageCompressorError.image_load_failed
        }

        var properties = source_properties(source, policy: policy)
        properties[kCGImageDestinationLossyCompressionQuality] = quality

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, type.identifier as CFString, 1, nil
        ) else {
            throw ImageCompressorError.compression_failed("Could not create \(type.identifier) destination")
        }

        CGImageDestinationAddImage(destination, cg_image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressorError.compression_failed("\(type.identifier) encoding failed")
        }
    }


}
