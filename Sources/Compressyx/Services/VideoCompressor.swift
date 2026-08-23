import Foundation

enum VideoCompressorError: LocalizedError {
    case ffmpeg_not_found
    case compression_failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ffmpeg_not_found:
            return "FFmpeg not found. Install via: brew install ffmpeg"
        case .compression_failed(let msg):
            return "Video compression failed: \(msg)"
        case .cancelled:
            return "Compression cancelled"
        }
    }
}

struct VideoCompressionParams: Sendable {
    let encoder: String
    let quality: Int
    let is_h265: Bool
    let output_url: URL
    let use_crf: Bool  // true for software encoders (VP9), false for VideoToolbox
    let crf: Int
    let max_height: Int?
    let fps_cap: Int
    let audio_args: [String]
}

enum VideoCompressor {
    static func find_ffmpeg() -> URL? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
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
        params: VideoCompressionParams,
        on_progress: @escaping @Sendable (Double) -> Void,
        on_process: @escaping @Sendable (Process) -> Void
    ) async throws -> URL {
        guard let ffmpeg_path = find_ffmpeg() else {
            throw VideoCompressorError.ffmpeg_not_found
        }

        let duration = await get_duration(ffmpeg: ffmpeg_path, input: input_url)

        var args = [
            "-i", input_url.path,
            "-c:v", params.encoder,
        ]

        if params.use_crf {
            // Software encoder (VP9, etc.) uses CRF
            args.append(contentsOf: ["-crf", "\(params.crf)", "-b:v", "0"])
        } else {
            // VideoToolbox uses -q:v
            args.append(contentsOf: ["-q:v", "\(params.quality)"])
        }

        if let max_height = params.max_height {
            // -2 keeps the width even (H.26x requires it); min() prevents upscaling a
            // smaller source into a bigger file.
            args.append(contentsOf: ["-vf", "scale=-2:'min(\(max_height),ih)'"])
        }

        if params.fps_cap > 0 {
            args.append(contentsOf: ["-r", "\(params.fps_cap)"])
        }

        args.append(contentsOf: params.audio_args)
        args.append(contentsOf: ["-y", "-progress", "pipe:1"])

        if params.is_h265 {
            args.append(contentsOf: ["-tag:v", "hvc1"])
        }

        args.append(params.output_url.path)

        let process = Process()
        process.executableURL = ffmpeg_path
        process.arguments = args

        let stdout_pipe = Pipe()
        let stderr_pipe = Pipe()
        process.standardOutput = stdout_pipe
        process.standardError = stderr_pipe

        try process.run()
        on_process(process)

        let handle = stdout_pipe.fileHandleForReading
        Task.detached {
            var buffer = Data()
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)

                if let text = String(data: buffer, encoding: .utf8) {
                    let lines = text.components(separatedBy: "\n")
                    for line in lines {
                        if line.hasPrefix("out_time_us="),
                           let value = Int64(line.replacingOccurrences(of: "out_time_us=", with: "")),
                           duration > 0
                        {
                            let progress = min(Double(value) / 1_000_000.0 / duration, 1.0)
                            on_progress(progress)
                        }
                    }
                    if let last_newline = text.lastIndex(of: "\n") {
                        let remaining = String(text[text.index(after: last_newline)...])
                        buffer = remaining.data(using: .utf8) ?? Data()
                    }
                }
            }
        }

        process.waitUntilExit()

        // Check if terminated by signal (cancel) vs normal exit
        if process.terminationReason == .uncaughtSignal {
            try? FileManager.default.removeItem(at: params.output_url)
            throw VideoCompressorError.cancelled
        }

        guard process.terminationStatus == 0 else {
            let error_data = stderr_pipe.fileHandleForReading.readDataToEndOfFile()
            let error_msg = String(data: error_data, encoding: .utf8) ?? "Unknown error"
            try? FileManager.default.removeItem(at: params.output_url)
            throw VideoCompressorError.compression_failed(error_msg)
        }

        return params.output_url
    }

    private static func get_duration(ffmpeg: URL, input: URL) async -> Double {
        let ffprobe_path = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.fileExists(atPath: ffprobe_path.path) else { return 0 }

        let process = Process()
        process.executableURL = ffprobe_path
        process.arguments = [
            "-v", "quiet",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            input.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let dur = Double(text) {
                return dur
            }
        } catch {}

        return 0
    }
}
