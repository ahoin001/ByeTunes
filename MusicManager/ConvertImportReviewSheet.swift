import SwiftUI

struct ConvertImportReviewSheet: View {
    let summary: ConvertImportSelectionSummary
    let onAdd: () -> Void
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
                summaryChip(count: summary.readyCount, label: "Ready", color: .green)
                summaryChip(count: summary.unsupportedCount, label: "Unsupported", color: .red)
            }

            Text(ConvertFileImport.supportedFormatsDescription())
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

    private func fileRow(_ item: ConvertImportPickedFile) -> some View {
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
                } else if item.disposition == .ready {
                    Text("Will be added to the conversion queue.")
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
                Button(action: onAdd) {
                    Label(
                        summary.readyCount == 1
                            ? "Add 1 File to Queue"
                            : "Add \(summary.readyCount) Files to Queue",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No files can be converted from this selection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for disposition: ConvertImportDisposition) -> Color {
        switch disposition {
        case .ready: return .green
        case .unsupported: return .red
        }
    }
}
