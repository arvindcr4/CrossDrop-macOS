import SwiftUI

/// Sheet displaying per-file progress for an active transfer with cancel support.
struct TransferProgressSheet: View {
    let progress: TransferProgress
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: progress.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(progress.direction == .incoming ? .green : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.direction == .incoming ? "Receiving Files" : "Sending Files")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(progress.direction == .incoming ? "From \(progress.peerAlias)" : "To \(progress.peerAlias)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Overall progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Overall Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress.overallFraction * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                ProgressView(value: progress.overallFraction)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(formatBytes(progress.bytesTransferred)) of \(formatBytes(progress.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("File \(min(progress.currentFileIndex + 1, progress.files.count)) of \(progress.files.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Per-file progress
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(progress.files) { file in
                        FileProgressRow(
                            file: file,
                            fileProgress: progress.fileProgress[file.id]
                        )
                    }
                }
            }
            .frame(maxHeight: 300)

            // Error message
            if let error = progress.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Actions
            HStack(spacing: 12) {
                if progress.isComplete {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                } else if progress.isFailed {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                } else {
                    Button("Cancel Transfer") {
                        progress.markCancelled()
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct FileProgressRow: View {
    let file: FileInfo
    let fileProgress: FileProgress?

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(1)

                if let fp = fileProgress {
                    if fp.completed {
                        Text("Completed")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if fp.bytesTransferred > 0 {
                        ProgressView(value: fp.fraction)
                            .progressViewStyle(.linear)
                            .scaleEffect(y: 0.6)
                    }
                }
            }

            Spacer()

            Text(formatBytes(file.size))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let fp = fileProgress, fp.completed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        } else if let fp = fileProgress, fp.bytesTransferred > 0 {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .font(.body)
        }
    }
}
