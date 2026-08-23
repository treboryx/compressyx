import Foundation

enum Dependencies {
    static let homebrew_url = "https://brew.sh"

    static func find_brew() -> URL? {
        let paths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func install(_ packages: [String]) async -> Bool {
        guard !packages.isEmpty, let brew = find_brew() else { return false }

        return await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = brew
                process.arguments = ["install"] + packages
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
