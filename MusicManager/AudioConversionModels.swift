import Foundation

enum ConversionTargetFormat: String, CaseIterable, Identifiable {
    case alacM4A
    case aacM4A

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alacM4A:
            return "ALAC (.m4a)"
        case .aacM4A:
            return "AAC (.m4a)"
        }
    }

    var outputExtension: String { "m4a" }
}

enum ConversionJobStatus: Equatable {
    case queued
    case converting
    case success
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .success, .failed:
            return true
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .queued:
            return "Queued"
        case .converting:
            return "Converting"
        case .success:
            return "Done"
        case .failed(let message):
            return message
        }
    }
}

struct ConversionJob: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var targetFormat: ConversionTargetFormat
    var outputURL: URL?
    var status: ConversionJobStatus
    var startedAt: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        targetFormat: ConversionTargetFormat,
        outputURL: URL? = nil,
        status: ConversionJobStatus = .queued,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.targetFormat = targetFormat
        self.outputURL = outputURL
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    var fileName: String {
        sourceURL.lastPathComponent
    }
}

struct ConversionResult: Equatable {
    let sourceURL: URL
    let outputURL: URL?
    let status: ConversionJobStatus
}
