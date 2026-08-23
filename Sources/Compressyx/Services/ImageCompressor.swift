import AppKit
import Foundation
import UniformTypeIdentifiers

enum ImageCompressorError: LocalizedError {
    case pngquant_not_found
    case compression_failed(String)
    case unsupported_format(String)
    case image_load_failed

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
        }
    }
}

struct ImageCompressionParams: Sendable {
    let quality: Double
    let pngquant_range: String
    let output_url: URL
}

enum ImageCompressor {
    static func find_pngquant() -> URL? {
        let paths = [
            "/opt/homebrew/bin/pngquant",
            "/usr/local/bin/pngquant"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func compress(
        input_url: URL,
        params: ImageCompressionParams,
        on_process: @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> URL {
        let ext = input_url.pathExtension.lowercased()

        switch ext {
        case "png":
            try await compress_png(input: input_url, output: params.output_url, pngquant_range: params.pngquant_range, on_process: on_process)
        case "jpg", "jpeg":
            try compress_jpeg(input: input_url, output: params.output_url, quality: params.quality)
        case "heic", "heif":
            try compress_heif(input: input_url, output: params.output_url, quality: params.quality)
        case "webp":
            try compress_webp(input: input_url, output: params.output_url, quality: params.quality)
        case "tiff", "tif", "bmp":
            let jpg_output = params.output_url.deletingPathExtension().appendingPathExtension("jpg")
            try compress_jpeg(input: input_url, output: jpg_output, quality: params.quality)
        default:
            throw ImageCompressorError.unsupported_format(ext)
        }

        return params.output_url
    }

    private static func compress_png(input: URL, output: URL, pngquant_range: String, on_process: @escaping @Sendable (Process) -> Void) async throws {
        guard let pngquant = find_pngquant() else {
            throw ImageCompressorError.pngquant_not_found
        }

        let process = Process()
        process.executableURL = pngquant
        process.arguments = [
            "--quality", pngquant_range,
            "--force",
            "--output", output.path,
            input.path
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
            try FileManager.default.copyItem(at: input, to: output)
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

    private static func compress_webp(input: URL, output: URL, quality: Double) throws {
        guard let image = NSImage(contentsOf: input),
              let tiff_data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff_data)
        else {
            throw ImageCompressorError.image_load_failed
        }

        let quality_factor = quality
        if let jpeg_data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality_factor]) {
            let jpeg_output = output.deletingPathExtension().appendingPathExtension("jpg")
            try jpeg_data.write(to: jpeg_output)
        }
    }
}
