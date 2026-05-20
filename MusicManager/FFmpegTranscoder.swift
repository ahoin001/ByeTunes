import Foundation
import ffmpegkit

enum FFmpegTranscoder {
    static var isAvailable: Bool { true }

    static func convert(
        inputURL: URL,
        outputURL: URL,
        target: ConversionTargetFormat
    ) async throws {
        let inputPath = inputURL.path
        let outputPath = outputURL.path

        let codecArgs: String
        switch target {
        case .alacM4A:
            codecArgs = "-c:a alac"
        case .aacM4A:
            codecArgs = "-c:a aac -b:a 256k"
        }

        // -map_metadata 0: preserve tags from source; -vn: audio-only output.
        let command = "-y -i \"\(inputPath)\" -vn \(codecArgs) -map_metadata 0 -movflags +faststart \"\(outputPath)\""
        try await runCommand(command)

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw AudioConversionError.conversionFailed("FFmpeg did not produce an output file")
        }
    }

    static func runCommand(_ command: String) async throws {
        Logger.shared.log("[FFmpegTranscoder] Running: ffmpeg \(command)")

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            FFmpegKit.executeAsync(command) { session in
                let returnCode = session?.getReturnCode()
                continuation.resume(returning: ReturnCode.isSuccess(returnCode))
            }
        }

        guard success else {
            let session = FFmpegKitConfig.getLastSession()
            let logs = session?.getAllLogsAsString() ?? ""
            let failTrace = session?.getFailStackTrace() ?? ""
            let detail = [logs, failTrace]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let message = detail.isEmpty ? "FFmpeg command failed" : String(detail.suffix(1200))
            Logger.shared.log("[FFmpegTranscoder] Failed: \(message)")
            throw AudioConversionError.conversionFailed(message)
        }
    }
}
