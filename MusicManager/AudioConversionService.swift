import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

enum AudioConversionError: LocalizedError {
    case unsupportedInput
    case noAudioTrack
    case cannotCreateExporter
    case cannotCreateReaderWriter
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            return "Unsupported input format"
        case .noAudioTrack:
            return "No audio track found"
        case .cannotCreateExporter:
            return "Failed to create export session"
        case .cannotCreateReaderWriter:
            return "Failed to prepare conversion pipeline"
        case .conversionFailed(let message):
            return message
        }
    }
}

final class AudioConversionService {
    static let shared = AudioConversionService()

    static let supportedInputTypes: [UTType] = {
        var types: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        if let ogg = UTType(filenameExtension: "ogg") { types.append(ogg) }
        if let opus = UTType(filenameExtension: "opus") { types.append(opus) }
        if let oga = UTType(filenameExtension: "oga") { types.append(oga) }
        return types
    }()

    private static let ffmpegPreferredExtensions: Set<String> = [
        "opus", "ogg", "oga", "ogv", "webm"
    ]

    private let fm = FileManager.default
    private let conversionDirectory: URL
    private let importStagingDirectory: URL

    private init() {
        conversionDirectory = fm.temporaryDirectory.appendingPathComponent("converted_audio", isDirectory: true)
        importStagingDirectory = fm.temporaryDirectory.appendingPathComponent("convert_import_staging", isDirectory: true)
        try? fm.createDirectory(at: conversionDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: importStagingDirectory, withIntermediateDirectories: true)
    }

    var isFFmpegAvailable: Bool {
        FFmpegTranscoder.isAvailable
    }

    var engineDescription: String {
        isFFmpegAvailable ? "FFmpegKit + AVFoundation" : "AVFoundation"
    }

    func convert(_ sourceURL: URL, to target: ConversionTargetFormat) async throws -> URL {
        let stagedInput = try stageInput(sourceURL)
        defer { try? fm.removeItem(at: stagedInput) }
        let outputURL = nextOutputURL(for: stagedInput, target: target)

        if fm.fileExists(atPath: outputURL.path) {
            try? fm.removeItem(at: outputURL)
        }

        if shouldPreferFFmpeg(for: stagedInput) {
            guard isFFmpegAvailable else {
                throw AudioConversionError.conversionFailed(
                    "This format requires FFmpeg. Rebuild the app with the FFmpegKit package linked."
                )
            }
            try await FFmpegTranscoder.convert(inputURL: stagedInput, outputURL: outputURL, target: target)
        } else {
            do {
                switch target {
                case .aacM4A:
                    try await convertToAAC(stagedInput, outputURL: outputURL)
                case .alacM4A:
                    try await convertToALAC(stagedInput, outputURL: outputURL)
                }
            } catch {
                guard isFFmpegAvailable else { throw error }
                Logger.shared.log("[AudioConversion] AVFoundation failed for \(stagedInput.lastPathComponent), retrying with FFmpeg: \(error.localizedDescription)")
                try await FFmpegTranscoder.convert(inputURL: stagedInput, outputURL: outputURL, target: target)
            }
        }

        try await embedTagsFromSource(sourceURL, into: outputURL)
        return outputURL
    }

    /// Stages a picked file like Music import (full filename preserved, tags intact).
    func stageImportSource(_ sourceURL: URL) throws -> URL {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let safeName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.lowercased()
        let stagedName = ext.isEmpty ? "\(UUID().uuidString)_\(safeName)" : "\(UUID().uuidString)_\(safeName)"
        let destURL = importStagingDirectory.appendingPathComponent(stagedName)

        if fm.fileExists(atPath: destURL.path) {
            try? fm.removeItem(at: destURL)
        }

        do {
            try fm.copyItem(at: sourceURL, to: destURL)
        } catch {
            let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            try data.write(to: destURL, options: .atomic)
        }

        return destURL
    }

    func removeStagedImports(urls: [URL]) {
        for url in urls {
            guard url.path.hasPrefix(importStagingDirectory.path) else { continue }
            try? fm.removeItem(at: url)
        }
    }

    func convertBatch(
        jobs: [ConversionJob],
        to target: ConversionTargetFormat,
        maxConcurrentJobs: Int = 1
    ) async -> [ConversionResult] {
        let limiter = AsyncLimiter(max(1, maxConcurrentJobs))
        var results: [ConversionResult] = jobs.map { job in
            ConversionResult(sourceURL: job.sourceURL, outputURL: nil, status: .failed("Not processed"))
        }

        await withTaskGroup(of: (Int, ConversionResult).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    await limiter.acquire()

                    do {
                        let outputURL = try await self.convert(job.sourceURL, to: target)
                        await limiter.release()
                        return (index, ConversionResult(sourceURL: job.sourceURL, outputURL: outputURL, status: .success))
                    } catch {
                        await limiter.release()
                        return (index, ConversionResult(sourceURL: job.sourceURL, outputURL: nil, status: .failed(error.localizedDescription)))
                    }
                }
            }

            for await (index, result) in group {
                results[index] = result
            }
        }

        return results
    }

    func removeTemporaryOutputs(urls: [URL]) {
        for url in urls where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    func logEngineStatus() {
        if isFFmpegAvailable {
            Logger.shared.log("[AudioConversion] FFmpegKit is linked; Opus/Ogg and fallback conversions enabled")
        } else {
            Logger.shared.log("[AudioConversion] FFmpegKit unavailable; using AVFoundation only")
        }
    }

    private func shouldPreferFFmpeg(for url: URL) -> Bool {
        Self.ffmpegPreferredExtensions.contains(url.pathExtension.lowercased())
    }

    /// Copies a security-scoped or external file into the conversion temp directory (e.g. at pick time).
    func stagePickedSource(_ sourceURL: URL) throws -> URL {
        try stageImportSource(sourceURL)
    }

    private func embedTagsFromSource(_ sourceURL: URL, into outputURL: URL) async throws {
        guard fm.fileExists(atPath: outputURL.path) else { return }
        guard FFmpegTranscoder.isAvailable else { return }
        do {
            try await AudioMetadataPreservation.copyTagsFromSource(sourceURL: sourceURL, outputURL: outputURL)
        } catch {
            Logger.shared.log("[AudioConversion] Tag embed skipped for \(outputURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func stageInput(_ sourceURL: URL) throws -> URL {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let stagedURL = conversionDirectory.appendingPathComponent("\(UUID().uuidString)_\(sourceURL.deletingPathExtension().lastPathComponent).\(ext)")

        if fm.fileExists(atPath: stagedURL.path) {
            try? fm.removeItem(at: stagedURL)
        }

        do {
            try fm.copyItem(at: sourceURL, to: stagedURL)
        } catch {
            let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            try data.write(to: stagedURL, options: .atomic)
        }

        return stagedURL
    }

    private func nextOutputURL(for inputURL: URL, target: ConversionTargetFormat) -> URL {
        let base = inputURL.deletingPathExtension().lastPathComponent
        let suffix = target == .alacM4A ? "alac" : "aac"
        return conversionDirectory.appendingPathComponent("\(base)_\(suffix)_\(UUID().uuidString).\(target.outputExtension)")
    }

    private func convertToAAC(_ inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioConversionError.cannotCreateExporter
        }

        session.outputURL = outputURL
        session.outputFileType = .m4a
        await AudioMetadataPreservation.applyExportSessionMetadata(from: inputURL, to: session)
        await session.export()

        if session.status != .completed {
            let message = session.error?.localizedDescription ?? "AAC export failed"
            throw AudioConversionError.conversionFailed(message)
        }
    }

    private func convertToALAC(_ inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw AudioConversionError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let pcmSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: pcmSettings)
        guard reader.canAdd(readerOutput) else {
            throw AudioConversionError.cannotCreateReaderWriter
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let outputSettings = try await alacOutputSettings(for: track)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw AudioConversionError.cannotCreateReaderWriter
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw AudioConversionError.conversionFailed(reader.error?.localizedDescription ?? "Unable to start reading source audio")
        }

        guard writer.startWriting() else {
            throw AudioConversionError.conversionFailed(writer.error?.localizedDescription ?? "Unable to start writing ALAC output")
        }

        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "AudioConversionService.ALACWriter")
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if reader.status == .reading {
                        if let sample = readerOutput.copyNextSampleBuffer() {
                            if !writerInput.append(sample) {
                                writerInput.markAsFinished()
                                reader.cancelReading()
                                writer.cancelWriting()
                                continuation.resume(throwing: AudioConversionError.conversionFailed(writer.error?.localizedDescription ?? "Failed to append ALAC sample"))
                                return
                            }
                        } else {
                            writerInput.markAsFinished()
                            writer.finishWriting {
                                if writer.status == .completed {
                                    continuation.resume(returning: ())
                                } else {
                                    continuation.resume(throwing: AudioConversionError.conversionFailed(writer.error?.localizedDescription ?? "ALAC writer did not complete"))
                                }
                            }
                            return
                        }
                    } else if reader.status == .failed {
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        continuation.resume(throwing: AudioConversionError.conversionFailed(reader.error?.localizedDescription ?? "Reader failed"))
                        return
                    } else if reader.status == .cancelled {
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        continuation.resume(throwing: AudioConversionError.conversionFailed("Reader cancelled"))
                        return
                    }
                }
            }
        }
    }

    private func alacOutputSettings(for track: AVAssetTrack) async throws -> [String: Any] {
        let formatDescriptions = try await track.load(.formatDescriptions)
        var sampleRate: Double = 44100
        var channels: Int = 2

        for description in formatDescriptions {
            guard let audioDescription = description as? CMAudioFormatDescription else { continue }
            if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription) {
                let asbd = asbdPtr.pointee
                if asbd.mSampleRate > 0 {
                    sampleRate = asbd.mSampleRate
                }
                if asbd.mChannelsPerFrame > 0 {
                    channels = Int(asbd.mChannelsPerFrame)
                }
                break
            }
        }

        return [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitDepthHintKey: 16
        ]
    }
}

actor AsyncLimiter {
    private var permits: Int

    init(_ permits: Int) {
        self.permits = permits
    }

    func acquire() async {
        while permits <= 0 {
            await Task.yield()
        }
        permits -= 1
    }

    func release() {
        permits += 1
    }
}
