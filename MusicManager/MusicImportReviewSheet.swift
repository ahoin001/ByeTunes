import SwiftUI

struct MusicImportReviewSession: Identifiable {
    let id = UUID()
    let summary: MusicImportSelectionSummary
}

struct MusicImportReviewSheet: View {
    let summary: MusicImportSelectionSummary
    let onImport: () -> Void
    let onOpenConvert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(summary.items) { item in
                            fileRow(item)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                actionBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Review Selection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                summaryChip(count: summary.readyCount, label: "Music", color: .green)
                summaryChip(count: summary.convertCount, label: "Convert", color: .orange)
                summaryChip(count: summary.unsupportedCount, label: "Unsupported", color: .red)
            }

            Text(MusicFileImport.supportedFormatsDescription())
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.weight(.bold))
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    private func fileRow(_ item: MusicImportPickedFile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.disposition.systemImage)
                .font(.title3)
                .foregroundColor(color(for: item.disposition))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(item.extensionLabel)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(item.disposition.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(color(for: item.disposition))
                }

                if let error = item.stagingError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if item.disposition == .needsConvert {
                    Text("Convert to ALAC or AAC, then add to Music queue.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if summary.hasReady {
                Button(action: onImport) {
                    Label(
                        summary.readyCount == 1
                            ? "Import 1 Song"
                            : "Import \(summary.readyCount) Songs",
                        systemImage: "music.note.list"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            }

            if summary.convertCount > 0 {
                Button(action: onOpenConvert) {
                    Label(
                        summary.convertCount == 1
                            ? "Open Convert Tab (1 file)"
                            : "Open Convert Tab (\(summary.convertCount) files)",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }

            if !summary.hasReady && summary.convertCount == 0 {
                Text("No files can be imported from this selection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for disposition: MusicImportDisposition) -> Color {
        switch disposition {
        case .readyForMusic: return .green
        case .needsConvert: return .orange
        case .unsupported: return .red
        }
    }
}
