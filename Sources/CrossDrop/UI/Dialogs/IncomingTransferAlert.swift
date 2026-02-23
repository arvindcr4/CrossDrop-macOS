import SwiftUI

/// Alert sheet displayed when a peer requests to send files.
struct IncomingTransferAlert: View {
    let transfer: AppState.IncomingTransferInfo
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            // Header
            VStack(spacing: 6) {
                Text("Incoming Transfer")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(transfer.alias) (\(transfer.deviceType)) wants to send you files")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // File list
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(transfer.files.prefix(10).enumerated()), id: \.element.id) { index, file in
                    if index > 0 {
                        Divider()
                    }
                    HStack {
                        Image(systemName: iconForMimeType(file.mimeType))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(file.name)
                            .font(.body)
                            .lineLimit(1)
                        Spacer()
                        Text(formatBytes(file.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                if transfer.files.count > 10 {
                    Divider()
                    Text("... and \(transfer.files.count - 10) more files")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            // Summary
            HStack {
                Text("\(transfer.files.count) file\(transfer.files.count == 1 ? "" : "s")")
                Text("--")
                Text(formatBytes(transfer.files.reduce(0) { $0 + $1.size }))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Actions
            HStack(spacing: 12) {
                Button("Decline") {
                    appState.rejectIncomingTransfer()
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Accept") {
                    appState.acceptIncomingTransfer()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func iconForMimeType(_ mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "music.note" }
        if mimeType.hasPrefix("text/") { return "doc.text" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("compressed") { return "doc.zipper" }
        return "doc"
    }
}
