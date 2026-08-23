import AppKit
import Foundation
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
            try await compress_png(input: input_url, output: params.output_url, pngquant_range: params.pngquant_range, on_process: on_process)
        case .jpeg:
            try compress_jpeg(input: input_url, output: params.output_url, quality: params.quality)
        case .heic:
            try compress_heif(input: input_url, output: params.output_url, quality: params.quality)
        case .webp:
            try await compress_webp(input: input_url, output: params.output_url, quality: params.quality, on_process: on_process)
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

    private static func compress_png(input: URL, output: URL, pngquant_range: String, on_process: @escaping @Sendable (Process) -> Void) async throws {
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
        process.arguments = [
            "--quality", pngquant_range,
            "--force",
            "--output", output.path,
            source.url.path
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

        guard process.terminationStatus == 0 || process.terminationStatus == 99 else {
            let error_data = stderr_pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: error_data, encoding: .utf8) ?? "Unknown error"
            throw ImageCompressorError.compression_failed(msg)
        }

        if !FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.copyItem(at: source.url, to: output)
        }
    }

    private static func compress_webp(input: URL, output: URL, quality: Double, on_process: @escaping @Sendable (Process) -> Void) async throws {
        guard let cwebp = find_cwebp() else {
            throw ImageCompressorError.cwebp_not_found
        }

        // cwebp reads PNG/JPEG/TIFF only, so HEIC and friends go through the PNG transcode.
        let source = try png_source(for: input)
        defer {
            if source.is_temporary {
                try? FileManager.default.removeItem(at: source.url)
            }
        }

        let process = Process()
        process.executableURL = cwebp
        process.arguments = [
            "-q", "\(Int((quality * 100).rounded()))",
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

    private static func compress_jpeg(input: URL, output: URL, quality: Double) throws {
        guard let image = NSImage(contentsOf: input),
              let tiff_data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff_data)
        else {
            throw ImageCompressorError.image_load_failed
        }

        guard let jpeg_data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            throw ImageCompressorError.compression_failed("JPEG encoding failed")
        }

        try jpeg_data.write(to: output)
    }

    private static func compress_heif(input: URL, output: URL, quality: Double) throws {
        guard let image = NSImage(contentsOf: input),
              let tiff_data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff_data),
              let cg_image = bitmap.cgImage
        else {
            throw ImageCompressorError.image_load_failed
        }

        let ci_image = CIImage(cgImage: cg_image)
        let context = CIContext()
        let color_space = cg_image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!

        try context.writeHEIFRepresentation(
            of: ci_image,
            to: output,
            format: .RGBA8,
            colorSpace: color_space,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        )
    }

}
