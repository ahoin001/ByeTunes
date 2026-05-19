import Foundation
import UniformTypeIdentifiers

enum ConvertImportDisposition: String, CaseIterable {
    case ready = "Ready"
    case unsupported = "Unsupported"

    var systemImage: String {
        switch self {
        case .ready: return "arrow.triangle.2.circlepath"
        case .unsupported: return "xmark.circle"
        }
    }
}

struct ConvertImportPickedFile: Identifiable, Hashable {
    let id = UUID()
    let displayName: String
    let fileExtension: String
    let disposition: ConvertImportDisposition
    let sourceURL: URL?
    var stagingError: String?

    var extensionLabel: String {
        fileExtension.isEmpty ? "NO EXT" : fileExtension.uppercased()
    }
}

struct ConvertImportStagingResult {
    let stagedURLs: [URL]
    let skippedCount: Int
    let failureMessages: [String]
}

struct ConvertImportSelectionSummary {
    let items: [ConvertImportPickedFile]
    let readyCount: Int
    let unsupportedCount: Int

    var hasReady: Bool { readyCount > 0 }
}

enum ConvertFileImport {
    static let supportedExtensions: Set<String> = {
        var extensions = MusicFileImport.directMusicExtensions
        extensions.formUnion(MusicFileImport.convertTabExtensions)
        extensions.formUnion(["webm", "ogv", "aif"])
        return extensions
    }()

    static var pickerTypes: [UTType] {
        AudioConversionService.supportedInputTypes + [.folder]
    }

    static func supportedFormatsDescription() -> String {
        let formats = supportedExtensions.sorted().map { ".\($0)" }.joined(separator: ", ")
        return "Supported: \(formats)."
    }

    static func disposition(forExtension ext: String) -> ConvertImportDisposition {
        supportedExtensions.contains(ext.lowercased()) ? .ready : .unsupported
    }

    static func analyzePickedURLs(_ urls: [URL]) -> ConvertImportSelectionSummary {
        var items: [ConvertImportPickedFile] = []

        func appendFile(_ url: URL) {
            let ext = url.pathExtension.lowercased()
            items.append(
                ConvertImportPickedFile(
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
                    ConvertImportPickedFile(
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
                        ConvertImportPickedFile(
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

    static func summary(from items: [ConvertImportPickedFile]) -> ConvertImportSelectionSummary {
        ConvertImportSelectionSummary(
            items: items,
            readyCount: items.filter { $0.disposition == .ready }.count,
            unsupportedCount: items.filter { $0.disposition == .unsupported }.count
        )
    }

    static func stageFiles(
        _ items: [ConvertImportPickedFile],
        to stagingDirectory: URL
    ) -> ConvertImportStagingResult {
        let fm = FileManager.default
        var stagedURLs: [URL] = []
        var skippedCount = 0
        var failureMessages: [String] = []

        do {
            try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.shared.log("[ConvertImport] Failed to create staging directory: \(error)")
            return ConvertImportStagingResult(
                stagedURLs: [],
                skippedCount: items.count,
                failureMessages: ["Could not create import folder: \(error.localizedDescription)"]
            )
        }

        for item in items where item.disposition == .ready {
            guard let sourceURL = item.sourceURL else {
                skippedCount += 1
                failureMessages.append("\(item.displayName): missing file reference")
                continue
            }

            switch MusicFileImport.stageFile(
                from: sourceURL,
                to: stagingDirectory,
                allowedExtensions: supportedExtensions
            ) {
            case .success(let staged):
                stagedURLs.append(staged)
                Logger.shared.log("[ConvertImport] Staged \(item.displayName)")
            case .failure(let failure):
                let message: String
                switch failure {
                case .message(let text): message = text
                }
                skippedCount += 1
                failureMessages.append("\(item.displayName): \(message)")
                Logger.shared.log("[ConvertImport] Failed to stage \(item.displayName): \(message)")
            }
        }

        Logger.shared.log("[ConvertImport] Staging completed. Staged \(stagedURLs.count), skipped \(skippedCount).")
        return ConvertImportStagingResult(
            stagedURLs: stagedURLs,
            skippedCount: skippedCount,
            failureMessages: failureMessages
        )
    }

    static func emptyStagingUserMessage(
        summary: ConvertImportSelectionSummary,
        staging: ConvertImportStagingResult
    ) -> String {
        var lines: [String] = []

        if summary.readyCount == 0 && summary.unsupportedCount > 0 {
            lines.append("No supported audio files in your selection.")
        } else if staging.stagedURLs.isEmpty {
            lines.append("Could not copy any selected files into the app.")
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

struct ConvertImportReviewSession: Identifiable {
    let id = UUID()
    let summary: ConvertImportSelectionSummary
}
