import SwiftUI
import UniformTypeIdentifiers

struct ConvertView: View {
    @Binding var songs: [SongMetadata]
    @Binding var status: String

    @State private var jobs: [ConversionJob] = []
    @State private var selectedFormat: ConversionTargetFormat = .alacM4A
    @State private var isPickerPresented = false
    @State private var isConverting = false
    @State private var showToast = false
    @State private var toastTitle = ""
    @State private var toastIcon = ""
    @State private var convertedCount = 0
    @State private var pickerErrorMessage: String?
    @State private var isStagingSelection = false

    private var successfulOutputs: [URL] {
        jobs.compactMap { job in
            if case .success = job.status {
                return job.outputURL
            }
            return nil
        }
    }

    private var canStartConversion: Bool {
        !isConverting && jobs.contains(where: { !$0.status.isTerminal })
    }

    private var queueSummaryText: String {
        let pending = jobs.filter { !$0.status.isTerminal }.count
        let completed = jobs.filter {
            if case .success = $0.status { return true }
            return false
        }.count
        return "\(jobs.count) files • \(pending) pending • \(completed) done"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Convert")
                        .font(.system(size: 34, weight: .bold))
                    Spacer()
                    Text(AudioConversionService.shared.engineDescription)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }

                Text("Convert audio files into Apple Music-friendly formats before injection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Opus, Ogg, and other formats are converted with FFmpegKit. FLAC/MP3/WAV use AVFoundation when possible.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                )

                VStack(spacing: 10) {
                    Button {
                        Logger.shared.log("[ConvertView] Select Files tapped")
                        isPickerPresented = true
                    } label: {
                        HStack {
                            if isStagingSelection {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 6)
                                Text("Preparing files...")
                                    .font(.body.weight(.medium))
                            } else {
                                Label("Select Files", systemImage: "plus")
                                    .font(.body.weight(.medium))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isConverting || isStagingSelection)

                    Picker("Output Format", selection: $selectedFormat) {
                        ForEach(ConversionTargetFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isConverting)

                    Button {
                        Task {
                            await convertQueue()
                        }
                    } label: {
                        HStack {
                            if isConverting {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Converting \(convertedCount)/\(jobs.count)")
                                    .font(.body.weight(.medium))
                            } else {
                                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.body.weight(.medium))
                            }
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canStartConversion)
                    .opacity(canStartConversion ? 1 : 0.6)

                    Button {
                        Task {
                            await addConvertedToMusicQueue()
                        }
                    } label: {
                        Label("Add Converted to Music Queue", systemImage: "music.note.list")
                            .font(.body.weight(.medium))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isConverting || successfulOutputs.isEmpty)
                    .opacity((!isConverting && !successfulOutputs.isEmpty) ? 1 : 0.6)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Conversion Queue")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        if !jobs.isEmpty {
                            Text(queueSummaryText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if jobs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.system(size: 42, weight: .light))
                                .foregroundColor(Color(.systemGray3))
                            Text("No files selected")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Select one or more files to prepare them for Apple Music.")
                                .font(.subheadline)
                                .foregroundColor(Color(.systemGray))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                                    conversionRow(job)
                                    if index < jobs.count - 1 {
                                        Divider().padding(.leading, 14)
                                    }
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)

            if showToast {
                HStack(spacing: 12) {
                    Image(systemName: toastIcon)
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)

                    Text(toastTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                .padding(.horizontal, 24)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .filePicker(
            isPresented: $isPickerPresented,
            types: AudioConversionService.supportedInputTypes,
            allowsMultiple: true,
            defaultAsCopy: false,
            context: .convert
        ) { urls in
            beginConvertSelection(with: urls)
        }
        .alert("File Selection Issue", isPresented: Binding(
            get: { pickerErrorMessage != nil },
            set: { if !$0 { pickerErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                pickerErrorMessage = nil
            }
        } message: {
            Text(pickerErrorMessage ?? "")
        }
        .onAppear {
            AudioConversionService.shared.logEngineStatus()
        }
    }

    @ViewBuilder
    private func conversionRow(_ job: ConversionJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon(for: job.status))
                    .foregroundColor(color(for: job.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(job.targetFormat.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(statusLabel(for: job.status))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color(for: job.status))
                    .lineLimit(1)
            }

            if case .failed(let message) = job.status {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private func beginConvertSelection(with urls: [URL]?) {
        guard let urls else {
            Logger.shared.log("[ConvertView] Picker cancelled")
            showToast(title: "Selection cancelled", icon: "xmark.circle")
            return
        }

        guard !urls.isEmpty else {
            Logger.shared.log("[ConvertView] Picker returned empty selection")
            pickerErrorMessage = "No files were returned by the Files picker."
            return
        }

        let pickedNames = urls.map(\.lastPathComponent)
        Logger.shared.log("[ConvertView] Picker returned \(urls.count) item(s): \(pickedNames.joined(separator: ", "))")

        let supported = urls.filter { isSupportedConvertInput($0) }
        let skipped = urls.count - supported.count

        if supported.isEmpty {
            let extSummary = summarizeExtensions(for: urls)
            Logger.shared.log("[ConvertView] No supported audio in selection: \(extSummary)")
            pickerErrorMessage = "No supported audio files in selection (\(extSummary)). Supported formats include MP3, FLAC, M4A, Opus, Ogg, WAV, and more."
            return
        }

        if skipped > 0 {
            Logger.shared.log("[ConvertView] Skipped \(skipped) unsupported file(s)")
            pickerErrorMessage = "Skipped \(skipped) unsupported file(s). Added \(supported.count) to the queue."
        }

        if FilePickerDebugSettings.convertStageAtPick {
            isStagingSelection = true
            Task {
                var staged: [URL] = []
                var failed = 0
                for url in supported {
                    do {
                        let copy = try AudioConversionService.shared.stagePickedSource(url)
                        staged.append(copy)
                    } catch {
                        failed += 1
                        Logger.shared.log("[ConvertView] Stage at pick failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    isStagingSelection = false
                    if staged.isEmpty {
                        pickerErrorMessage = "Could not copy selected files into the app. Try enabling a different picker mode in Settings → DEBUG."
                        return
                    }
                    if failed > 0 {
                        pickerErrorMessage = "Added \(staged.count) file(s); \(failed) could not be prepared."
                    }
                    enqueue(urls: staged)
                }
            }
            return
        }

        enqueue(urls: supported)
    }

    private func isSupportedConvertInput(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return true
        }
        return isLikelyAudioExtension(ext)
    }

    private func enqueue(urls: [URL]) {
        let newJobs = urls.map { url in
            ConversionJob(sourceURL: url, targetFormat: selectedFormat)
        }
        jobs.append(contentsOf: newJobs)

        let extensionSummary = summarizeExtensions(for: urls)
        Logger.shared.log("[ConvertView] Enqueued \(newJobs.count) file(s) for conversion. Types: \(extensionSummary)")
        showToast(title: "Added \(newJobs.count) file(s) • \(extensionSummary)", icon: "checkmark.circle.fill")
    }

    private func summarizeExtensions(for urls: [URL]) -> String {
        let counts = Dictionary(grouping: urls) { url -> String in
            let ext = url.pathExtension.lowercased()
            return ext.isEmpty ? "unknown" : ext
        }.mapValues(\.count)

        if counts.isEmpty { return "unknown" }
        return counts
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { key, value in
                key == "unknown" ? "\(value)x no-ext" : "\(value)x .\(key)"
            }
            .joined(separator: ", ")
    }

    private func isLikelyAudioExtension(_ ext: String) -> Bool {
        let known: Set<String> = [
            "mp3", "wav", "aiff", "aif", "aifc", "m4a",
            "flac", "ogg", "opus", "oga", "aac", "alac",
            "caf", "webm", "mp4", "m4b"
        ]
        return known.contains(ext)
    }

    private func convertQueue() async {
        isConverting = true
        convertedCount = 0
        status = "Converting files..."

        let pendingIndices = jobs.indices.filter { !jobs[$0].status.isTerminal }
        for index in pendingIndices {
            jobs[index].status = .converting
            jobs[index].targetFormat = selectedFormat
        }

        let results = await AudioConversionService.shared.convertBatch(
            jobs: pendingIndices.map { jobs[$0] },
            to: selectedFormat,
            maxConcurrentJobs: 1
        )

        for (resultIndex, jobIndex) in pendingIndices.enumerated() {
            let result = results[resultIndex]
            jobs[jobIndex].targetFormat = selectedFormat
            jobs[jobIndex].startedAt = jobs[jobIndex].startedAt ?? Date()

            switch result.status {
            case .success:
                jobs[jobIndex].outputURL = result.outputURL
                jobs[jobIndex].status = .success
                jobs[jobIndex].completedAt = Date()
                convertedCount += 1
            case .failed(let message):
                jobs[jobIndex].status = .failed(message)
                jobs[jobIndex].completedAt = Date()
                Logger.shared.log("[ConvertView] Conversion failed for \(jobs[jobIndex].fileName): \(message)")
            default:
                break
            }
        }

        isConverting = false
        let failures = jobs.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
        status = failures == 0 ? "Conversion complete" : "Conversion finished with \(failures) failure(s)"
        showToast(
            title: failures == 0 ? "Converted \(convertedCount) file(s)" : "Converted \(convertedCount), Failed \(failures)",
            icon: failures == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
    }

    private func addConvertedToMusicQueue() async {
        let outputs = successfulOutputs
        guard !outputs.isEmpty else { return }

        var convertedSongs: [SongMetadata] = []
        for outputURL in outputs {
            if let song = try? await SongMetadata.fromURL(outputURL) {
                convertedSongs.append(song)
            } else {
                Logger.shared.log("[ConvertView] Failed to parse converted file: \(outputURL.lastPathComponent)")
            }
        }

        guard !convertedSongs.isEmpty else {
            showToast(title: "No converted files were queue-ready", icon: "xmark.circle.fill")
            return
        }

        songs.append(contentsOf: convertedSongs)
        status = "Added \(convertedSongs.count) converted song(s) to queue"
        showToast(title: "Added \(convertedSongs.count) to Music queue", icon: "music.note.list")
    }

    private func icon(for status: ConversionJobStatus) -> String {
        switch status {
        case .queued:
            return "clock"
        case .converting:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func color(for status: ConversionJobStatus) -> Color {
        switch status {
        case .queued:
            return .secondary
        case .converting:
            return .accentColor
        case .success:
            return .green
        case .failed:
            return .red
        }
    }

    private func statusLabel(for status: ConversionJobStatus) -> String {
        switch status {
        case .failed:
            return "Failed"
        default:
            return status.displayText
        }
    }

    private func showToast(title: String, icon: String) {
        withAnimation(.spring()) {
            toastTitle = title
            toastIcon = icon
            showToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.5)) {
                showToast = false
            }
        }
    }
}
