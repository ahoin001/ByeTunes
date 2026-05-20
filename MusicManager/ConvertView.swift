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
                            Button("Clear", role: .destructive) {
                                clearQueue()
                            }
                            .font(.subheadline.weight(.semibold))
                            .disabled(isConverting)
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
                if case .converting = job.status {
                    ProgressView()
                        .scaleEffect(0.85)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: icon(for: job.status))
                        .foregroundColor(color(for: job.status))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(job.displaySubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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

        stageAndEnqueue(urls: supported)
    }

    private func stageAndEnqueue(urls: [URL]) {
        isStagingSelection = true
        Task {
            var stagedJobs: [(URL, PreservedTrackMetadata?)] = []
            var failed = 0

            for url in urls {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let stagedURL = try AudioConversionService.shared.stageImportSource(url)
                    let metadata = await AudioMetadataPreservation.capture(from: stagedURL)
                    stagedJobs.append((stagedURL, metadata))
                } catch {
                    failed += 1
                    Logger.shared.log("[ConvertView] Stage failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isStagingSelection = false
                if stagedJobs.isEmpty {
                    pickerErrorMessage = "Could not copy selected files into the app. Try a different picker mode in Settings → DEBUG."
                    return
                }
                if failed > 0 {
                    pickerErrorMessage = "Added \(stagedJobs.count) file(s); \(failed) could not be prepared."
                }
                enqueue(stagedJobs: stagedJobs)
            }
        }
    }

    private func isSupportedConvertInput(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return true
        }
        return isLikelyAudioExtension(ext)
    }

    private func enqueue(stagedJobs: [(URL, PreservedTrackMetadata?)]) {
        let newJobs = stagedJobs.map { stagedURL, metadata in
            ConversionJob(
                sourceURL: stagedURL,
                targetFormat: selectedFormat,
                preservedMetadata: metadata
            )
        }
        jobs.append(contentsOf: newJobs)

        let urls = stagedJobs.map(\.0)
        let extensionSummary = summarizeExtensions(for: urls)
        Logger.shared.log("[ConvertView] Enqueued \(newJobs.count) file(s) for conversion. Types: \(extensionSummary)")
        showToast(title: "Added \(newJobs.count) file(s) • \(extensionSummary)", icon: "checkmark.circle.fill")
    }

    private func clearQueue() {
        guard !isConverting else { return }
        let sourceURLs = jobs.map(\.sourceURL)
        let outputURLs = jobs.compactMap(\.outputURL)
        AudioConversionService.shared.removeStagedImports(urls: sourceURLs)
        AudioConversionService.shared.removeTemporaryOutputs(urls: outputURLs)
        jobs.removeAll()
        convertedCount = 0
        showToast(title: "Queue cleared", icon: "trash")
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
        await MainActor.run {
            isConverting = true
            convertedCount = 0
            status = "Converting files..."
        }

        let pendingIndices = await MainActor.run {
            jobs.indices.filter { !jobs[$0].status.isTerminal }
        }

        let total = pendingIndices.count
        var completedInRun = 0

        for (runIndex, jobIndex) in pendingIndices.enumerated() {
            await MainActor.run {
                jobs[jobIndex].status = .converting
                jobs[jobIndex].targetFormat = selectedFormat
                jobs[jobIndex].startedAt = Date()
                status = "Converting \(runIndex + 1)/\(total): \(jobs[jobIndex].displayTitle)"
            }

            let sourceURL = await MainActor.run { jobs[jobIndex].sourceURL }
            do {
                let outputURL = try await AudioConversionService.shared.convert(sourceURL, to: selectedFormat)
                await MainActor.run {
                    jobs[jobIndex].outputURL = outputURL
                    jobs[jobIndex].status = .success
                    jobs[jobIndex].completedAt = Date()
                    convertedCount += 1
                    completedInRun += 1
                }
            } catch {
                let message = error.localizedDescription
                let failedTitle = await MainActor.run { jobs[jobIndex].displayTitle }
                await MainActor.run {
                    jobs[jobIndex].status = .failed(message)
                    jobs[jobIndex].completedAt = Date()
                }
                Logger.shared.log("[ConvertView] Conversion failed for \(failedTitle): \(message)")
            }
        }

        await MainActor.run {
            isConverting = false
            let failures = jobs.filter {
                if case .failed = $0.status { return true }
                return false
            }.count
            status = failures == 0 ? "Conversion complete" : "Conversion finished with \(failures) failure(s)"
            showToast(
                title: failures == 0 ? "Converted \(completedInRun) file(s)" : "Converted \(completedInRun), Failed \(failures)",
                icon: failures == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
        }
    }

    private func addConvertedToMusicQueue() async {
        let successfulJobs = await MainActor.run {
            jobs.filter {
                if case .success = $0.status, $0.outputURL != nil { return true }
                return false
            }
        }
        guard !successfulJobs.isEmpty else { return }

        var convertedSongs: [SongMetadata] = []
        for job in successfulJobs {
            guard let outputURL = job.outputURL else { continue }
            if let preserved = job.preservedMetadata {
                var song = preserved.makeSongMetadata(for: outputURL)
                if song.durationMs == 0, let parsed = try? await SongMetadata.fromURL(outputURL, includeArtwork: false) {
                    song.durationMs = parsed.durationMs
                }
                convertedSongs.append(song)
            } else if let song = try? await SongMetadata.fromURL(outputURL) {
                convertedSongs.append(song)
            } else {
                Logger.shared.log("[ConvertView] Failed to parse converted file: \(outputURL.lastPathComponent)")
            }
        }

        guard !convertedSongs.isEmpty else {
            await MainActor.run {
                showToast(title: "No converted files were queue-ready", icon: "xmark.circle.fill")
            }
            return
        }

        await MainActor.run {
            songs.append(contentsOf: convertedSongs)
            status = "Added \(convertedSongs.count) converted song(s) to queue"
            showToast(title: "Added \(convertedSongs.count) to Music queue", icon: "music.note.list")
        }
    }

    private func icon(for status: ConversionJobStatus) -> String {
        switch status {
        case .queued:
            return "clock"
        case .converting:
            return "hourglass"
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
