import Foundation
import UniformTypeIdentifiers

// MARK: - File classification

enum MusicImportDisposition: String, CaseIterable {
    case readyForMusic = "Music"
    case needsConvert = "Convert"
    case unsupported = "Unsupported"

    var systemImage: String {
        switch self {
        case .readyForMusic: return "music.note"
        case .needsConvert: return "arrow.triangle.2.circlepath"
        case .unsupported: return "xmark.circle"
        }
    }
}

struct MusicImportPickedFile: Identifiable, Hashable {
    let id = UUID()
    let displayName: String
    let fileExtension: String
    let disposition: MusicImportDisposition
    let sourceURL: URL?
    var stagingError: String?

    var extensionLabel: String {
        fileExtension.isEmpty ? "NO EXT" : fileExtension.uppercased()
    }
}

struct MusicImportStagingResult {
    let stagedURLs: [URL]
    let skippedCount: Int
    let failureMessages: [String]
}

struct MusicImportSelectionSummary {
    let items: [MusicImportPickedFile]
    let readyCount: Int
    let convertCount: Int
    let unsupportedCount: Int

    var hasReady: Bool { readyCount > 0 }
}

enum MusicFileImport {
    static let directMusicExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aiff", "aifc", "flac"
    ]

    static let convertTabExtensions: Set<String> = [
        "opus", "ogg", "oga", "ogv", "webm"
    ]

    static var pickerTypes: [UTType] {
        var types = AudioConversionService.supportedInputTypes
        types.append(.folder)
        return types
    }

    static func disposition(forExtension ext: String) -> MusicImportDisposition {
        let normalized = ext.lowercased()
        if directMusicExtensions.contains(normalized) { return .readyForMusic }
        if convertTabExtensions.contains(normalized) { return .needsConvert }
        return .unsupported
    }

    static func disposition(for url: URL) -> MusicImportDisposition {
        disposition(forExtension: url.pathExtension)
    }

    static func supportedFormatsDescription() -> String {
        let music = directMusicExtensions.sorted().map { ".\($0)" }.joined(separator: ", ")
        let convert = convertTabExtensions.sorted().map { ".\($0)" }.joined(separator: ", ")
        return "Music tab: \(music). Use Convert tab for \(convert)."
    }

    // MARK: - Analyze picker results

    static func analyzePickedURLs(_ urls: [URL]) -> MusicImportSelectionSummary {
        var items: [MusicImportPickedFile] = []

        func appendFile(_ url: URL) {
            let ext = url.pathExtension.lowercased()
            items.append(
                MusicImportPickedFile(
                    displayName: url.lastPathComponent,
                    fileExtension: ext,
                    disposition: disposition(forExtension: ext),
                    sourceURL: url,
                    stagingError: nil
                )
            )
        }

        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                items.append(
                    MusicImportPickedFile(
                        displayName: url.lastPathComponent,
                        fileExtension: url.pathExtension.lowercased(),
                        disposition: .unsupported,
                        sourceURL: url,
                        stagingError: "File not found or not downloaded from iCloud"
                    )
                )
                continue
            }

            if isDir.boolValue {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                var foundAudio = false
                while let fileURL = enumerator?.nextObject() as? URL {
                    var isRegular = false
                    if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                       values.isRegularFile == true {
                        isRegular = true
                    }
                    if isRegular || !fileURL.hasDirectoryPath {
                        appendFile(fileURL)
                        foundAudio = true
                    }
                }
                if !foundAudio {
                    items.append(
                        MusicImportPickedFile(
                            displayName: url.lastPathComponent,
                            fileExtension: "folder",
                            disposition: .unsupported,
                            sourceURL: url,
                            stagingError: "Folder contains no files"
                        )
                    )
                }
            } else {
                appendFile(url)
            }
        }

        return summary(from: items)
    }

    static func summary(from items: [MusicImportPickedFile]) -> MusicImportSelectionSummary {
        MusicImportSelectionSummary(
            items: items,
            readyCount: items.filter { $0.disposition == .readyForMusic }.count,
            convertCount: items.filter { $0.disposition == .needsConvert }.count,
            unsupportedCount: items.filter { $0.disposition == .unsupported }.count
        )
    }

    // MARK: - Staging (security-scoped, sideload-friendly — asCopy: false in picker)

    static func stageFiles(
        _ items: [MusicImportPickedFile],
        to stagingDirectory: URL
    ) -> MusicImportStagingResult {
        let fm = FileManager.default
        var stagedURLs: [URL] = []
        var skippedCount = 0
        var failureMessages: [String] = []

        do {
            try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.shared.log("[MusicImport] Failed to create staging directory: \(error)")
            return MusicImportStagingResult(
                stagedURLs: [],
                skippedCount: items.count,
                failureMessages: ["Could not create import folder: \(error.localizedDescription)"]
            )
        }

        for item in items where item.disposition == .readyForMusic {
            guard let sourceURL = item.sourceURL else {
                skippedCount += 1
                failureMessages.append("\(item.displayName): missing file reference")
                continue
            }

            switch stageFile(from: sourceURL, to: stagingDirectory) {
            case .success(let staged):
                stagedURLs.append(staged)
                Logger.shared.log("[MusicImport] Staged \(item.displayName)")
            case .failure(let failure):
                let message: String
                switch failure {
                case .message(let text): message = text
                }
                skippedCount += 1
                failureMessages.append("\(item.displayName): \(message)")
                Logger.shared.log("[MusicImport] Failed to stage \(item.displayName): \(message)")
            }
        }

        Logger.shared.log("[MusicImport] Staging completed. Staged \(stagedURLs.count), skipped \(skippedCount).")
        return MusicImportStagingResult(
            stagedURLs: stagedURLs,
            skippedCount: skippedCount,
            failureMessages: failureMessages
        )
    }

    enum StagingFailure: Error {
        case message(String)
    }

    static func stageFile(from sourceURL: URL, to stagingDirectory: URL) -> Result<URL, StagingFailure> {
        let ext = sourceURL.pathExtension.lowercased()
        guard directMusicExtensions.contains(ext) else {
            return .failure(.message("Unsupported format (.\(ext.isEmpty ? "?" : ext))"))
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure(.message("File not found — download it from iCloud first"))
        }

        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if !accessGranted {
            Logger.shared.log("[MusicImport] Security-scoped access not granted for \(sourceURL.lastPathComponent); attempting copy anyway")
        }

        let safeName = sourceURL.lastPathComponent
        let stagedName = "\(UUID().uuidString)_\(safeName)"
        let destURL = stagingDirectory.appendingPathComponent(stagedName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return .success(destURL)
        } catch {
            do {
                let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                guard !data.isEmpty else {
                    return .failure(.message("File is empty or unreadable"))
                }
                try data.write(to: destURL, options: .atomic)
                Logger.shared.log("[MusicImport] Data fallback copy succeeded for \(safeName)")
                return .success(destURL)
            } catch let readError {
                let hint = accessGranted ? "" : " Allow file access when prompted, or move the file to On My iPhone."
                return .failure(.message("\(readError.localizedDescription)\(hint)"))
            }
        }
    }

    static func emptyStagingUserMessage(
        summary: MusicImportSelectionSummary,
        staging: MusicImportStagingResult
    ) -> String {
        var lines: [String] = []

        if summary.readyCount == 0 && summary.convertCount > 0 {
            lines.append("These formats must be converted before adding to Music.")
            lines.append("Open the Convert tab, convert to ALAC or AAC, then use “Add Converted to Music Queue”.")
        } else if summary.readyCount == 0 && summary.unsupportedCount > 0 {
            lines.append("No supported music files in your selection.")
        } else if staging.stagedURLs.isEmpty {
            lines.append("Could not copy any selected files into the app.")
        }

        if summary.convertCount > 0 {
            lines.append("\(summary.convertCount) file(s) need the Convert tab (\(convertTabExtensions.sorted().map { ".\($0)" }.joined(separator: ", "))).")
        }
        if summary.unsupportedCount > 0 {
            lines.append("\(summary.unsupportedCount) unsupported file(s).")
        }
        if !staging.failureMessages.isEmpty {
            let preview = staging.failureMessages.prefix(4).joined(separator: "\n")
            lines.append(preview)
            if staging.failureMessages.count > 4 {
                lines.append("…and \(staging.failureMessages.count - 4) more (see Debug Logs).")
            }
        }

        lines.append(supportedFormatsDescription())
        return lines.joined(separator: "\n\n")
    }
}
