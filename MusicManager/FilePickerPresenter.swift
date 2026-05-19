import SwiftUI
import UniformTypeIdentifiers

// MARK: - Debug settings (UserDefaults / @AppStorage)

enum FilePickerPresentationMode: String, CaseIterable, Identifiable {
    case auto
    case fileImporter
    case fullScreenHost
    case backgroundHost
    case sheetHost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .fileImporter: return "fileImporter"
        case .fullScreenHost: return "Full-screen host"
        case .backgroundHost: return "Background host"
        case .sheetHost: return "Sheet host"
        }
    }
}

enum FilePickerAsCopyOverride: String, CaseIterable, Identifiable {
    case auto
    case copy
    case inPlace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .copy: return "Copy (asCopy: true)"
        case .inPlace: return "In place (asCopy: false)"
        }
    }

    var asCopy: Bool? {
        switch self {
        case .auto: return nil
        case .copy: return true
        case .inPlace: return false
        }
    }
}

/// Where the picker is shown — used by `auto` presentation mode.
enum FilePickerUsageContext: String {
    case music
    case convert
    case ringtones
    case settingsPairing
    case settingsFolder
    case generic
}

enum FilePickerDebugSettings {
    static let presentationKey = "debugPickerPresentation"
    static let asCopyOverrideKey = "debugPickerAsCopyOverride"
    static let verboseLoggingKey = "debugPickerVerboseLogging"
    static let convertStageAtPickKey = "debugConvertStageAtPick"
    static let convertShowReviewSheetKey = "debugConvertShowReviewSheet"
    static let lastEventKey = "debugPickerLastEvent"

    static var presentation: FilePickerPresentationMode {
        let raw = UserDefaults.standard.string(forKey: presentationKey) ?? FilePickerPresentationMode.auto.rawValue
        return FilePickerPresentationMode(rawValue: raw) ?? .auto
    }

    static var asCopyOverride: FilePickerAsCopyOverride {
        let raw = UserDefaults.standard.string(forKey: asCopyOverrideKey) ?? FilePickerAsCopyOverride.auto.rawValue
        return FilePickerAsCopyOverride(rawValue: raw) ?? .auto
    }

    static var verboseLogging: Bool {
        UserDefaults.standard.bool(forKey: verboseLoggingKey)
    }

    static var convertStageAtPick: Bool {
        UserDefaults.standard.bool(forKey: convertStageAtPickKey)
    }

    static var convertShowReviewSheet: Bool {
        UserDefaults.standard.bool(forKey: convertShowReviewSheetKey)
    }

    static func recordEvent(_ message: String) {
        let stamp = Self.timestamp()
        let line = "\(stamp) — \(message)"
        UserDefaults.standard.set(line, forKey: lastEventKey)
        Logger.shared.log("[FilePicker] \(message)")
    }

    static func logVerbose(_ message: String) {
        guard verboseLogging else { return }
        Logger.shared.log("[FilePicker] \(message)")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    static func resolvedPresentation(for context: FilePickerUsageContext) -> FilePickerPresentationMode {
        let configured = presentation
        if configured != .auto { return configured }
        switch context {
        case .convert:
            return .fileImporter
        case .music, .ringtones, .settingsPairing, .settingsFolder, .generic:
            return .fullScreenHost
        }
    }

    static func resolvedAsCopy(context: FilePickerUsageContext, callerDefault: Bool) -> Bool {
        if let override = asCopyOverride.asCopy {
            return override
        }
        switch context {
        case .settingsFolder, .convert:
            return callerDefault
        case .music, .ringtones, .settingsPairing, .generic:
            return callerDefault
        }
    }
}

// MARK: - View modifier

struct FilePickerPresenterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let types: [UTType]
    var allowsMultiple: Bool
    var defaultAsCopy: Bool
    let context: FilePickerUsageContext
    let onResult: ([URL]?) -> Void

    private var presentation: FilePickerPresentationMode {
        FilePickerDebugSettings.resolvedPresentation(for: context)
    }

    private var effectiveAsCopy: Bool {
        FilePickerDebugSettings.resolvedAsCopy(context: context, callerDefault: defaultAsCopy)
    }

    func body(content: Content) -> some View {
        let mode = presentation
        FilePickerDebugSettings.logVerbose(
            "Presenting mode=\(mode.label) context=\(context.rawValue) asCopy=\(effectiveAsCopy) multiple=\(allowsMultiple)"
        )

        return content
            .modifier(
                FilePickerPresentationRouter(
                    isPresented: $isPresented,
                    types: types,
                    allowsMultiple: allowsMultiple,
                    asCopy: effectiveAsCopy,
                    mode: mode,
                    onResult: handleResult
                )
            )
    }

    private func handleResult(_ urls: [URL]?) {
        isPresented = false
        if let urls, !urls.isEmpty {
            let names = urls.map(\.lastPathComponent).joined(separator: ", ")
            FilePickerDebugSettings.recordEvent("Picked \(urls.count): \(names)")
        } else if urls != nil {
            FilePickerDebugSettings.recordEvent("Picked 0 files")
        } else {
            FilePickerDebugSettings.recordEvent("Cancelled")
        }
        onResult(urls)
    }
}

private struct FilePickerPresentationRouter: ViewModifier {
    @Binding var isPresented: Bool
    let types: [UTType]
    let allowsMultiple: Bool
    let asCopy: Bool
    let mode: FilePickerPresentationMode
    let onResult: ([URL]?) -> Void

    func body(content: Content) -> some View {
        switch mode {
        case .fileImporter:
            content.fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: types,
                allowsMultipleSelection: allowsMultiple
            ) { result in
                switch result {
                case .success(let urls):
                    onResult(urls)
                case .failure(let error):
                    if FilePickerPresenter.isUserCancelled(error) {
                        onResult(nil)
                    } else {
                        FilePickerDebugSettings.recordEvent("fileImporter error: \(error.localizedDescription)")
                        onResult(nil)
                    }
                }
            }
        case .fullScreenHost:
            content.fullScreenCover(isPresented: $isPresented) {
                DocumentPicker(
                    types: types,
                    allowsMultiple: allowsMultiple,
                    asCopy: asCopy,
                    completion: onResult
                )
                .ignoresSafeArea()
            }
        case .sheetHost:
            content.sheet(isPresented: $isPresented) {
                DocumentPicker(
                    types: types,
                    allowsMultiple: allowsMultiple,
                    asCopy: asCopy,
                    completion: onResult
                )
            }
        case .backgroundHost, .auto:
            content.background {
                if isPresented {
                    DocumentPicker(
                        types: types,
                        allowsMultiple: allowsMultiple,
                        asCopy: asCopy,
                        completion: onResult
                    )
                    .frame(width: 0, height: 0)
                }
            }
        }
    }
}

enum FilePickerPresenter {
    static func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.userCancelled.rawValue {
            return true
        }
        return nsError.code == NSUserCancelledError
    }
}

extension View {
    /// Presents a file picker using debug/production presentation settings.
    func filePicker(
        isPresented: Binding<Bool>,
        types: [UTType],
        allowsMultiple: Bool = false,
        defaultAsCopy: Bool = true,
        context: FilePickerUsageContext,
        onResult: @escaping ([URL]?) -> Void
    ) -> some View {
        modifier(
            FilePickerPresenterModifier(
                isPresented: isPresented,
                types: types,
                allowsMultiple: allowsMultiple,
                defaultAsCopy: defaultAsCopy,
                context: context,
                onResult: onResult
            )
        )
    }

    /// Single-file convenience (e.g. pairing file, folder).
    func filePicker(
        isPresented: Binding<Bool>,
        types: [UTType],
        defaultAsCopy: Bool = true,
        context: FilePickerUsageContext,
        onResult: @escaping (URL?) -> Void
    ) -> some View {
        filePicker(
            isPresented: isPresented,
            types: types,
            allowsMultiple: false,
            defaultAsCopy: defaultAsCopy,
            context: context
        ) { urls in
            onResult(urls?.first)
        }
    }
}
