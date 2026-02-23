import SwiftUI

/// Displays active and completed transfers.
struct TransferHistoryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.activeTransfers.isEmpty {
                activeTransfersSection
                Divider()
            }

            if appState.transferHistory.isEmpty && appState.activeTransfers.isEmpty {
                emptyHistoryState
            } else {
                historySection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var activeTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Transfers")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ForEach(appState.activeTransfers) { progress in
                ActiveTransferRow(progress: progress)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)
        }
        .background(Color.blue.opacity(0.03))
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transfer History")
                    .font(.headline)
                Spacer()
                if !appState.transferHistory.isEmpty {
                    Button("Clear") {
                        appState.transferHistory.removeAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            List(appState.transferHistory) { record in
                HistoryRow(record: record)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var emptyHistoryState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No transfers yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Select a device and send files,\nor wait for incoming transfers")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActiveTransferRow: View {
    let progress: TransferProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: progress.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(progress.direction == .incoming ? .green : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.direction == .incoming ? "Receiving from \(progress.peerAlias)" : "Sending to \(progress.peerAlias)")
                        .font(.body)
                        .fontWeight(.medium)

                    if let fileName = progress.currentFileName {
                        Text(fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("\(Int(progress.overallFraction * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress.overallFraction)
                .progressViewStyle(.linear)

            HStack {
                Text("\(progress.files.count) file\(progress.files.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(formatBytes(progress.bytesTransferred))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("of")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(formatBytes(progress.totalBytes))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HistoryRow: View {
    let record: TransferRecord

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.direction == .incoming ? "Received from \(record.peerAlias)" : "Sent to \(record.peerAlias)")
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(record.files.count) file\(record.files.count == 1 ? "" : "s")")
                    Text("--")
                    Text(formatBytes(record.files.reduce(0) { $0 + $1.size }))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                statusLabel
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch record.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
        default:
            Image(systemName: "circle.fill")
                .foregroundStyle(.gray)
                .font(.title3)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch record.status {
        case .completed:
            Text("Completed")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Text("Failed")
                .font(.caption2)
                .foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled")
                .font(.caption2)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
