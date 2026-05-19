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
                        isPickerPresented = true
                    } label: {
                        Label("Select Files", systemImage: "plus")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isConverting)

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
        .sheet(isPresented: $isPickerPresented) {
            DocumentPicker(types: AudioConversionService.supportedInputTypes, allowsMultiple: true, asCopy: false) { urls in
                enqueue(urls: urls)
            }
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

    private func enqueue(urls: [URL]?) {
        guard let urls, !urls.isEmpty else { return }

        let newJobs = urls.map { url in
            ConversionJob(sourceURL: url, targetFormat: selectedFormat)
        }
        jobs.append(contentsOf: newJobs)
        showToast(title: "Added \(newJobs.count) file(s)", icon: "checkmark.circle.fill")
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
