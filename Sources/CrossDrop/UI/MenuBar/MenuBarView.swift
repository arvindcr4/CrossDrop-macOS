import SwiftUI

/// Menu bar extra popover with quick access to peer list and send file action.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text("CrossDrop")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Active transfers
            if !appState.activeTransfers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Transfers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    ForEach(appState.activeTransfers) { progress in
                        MenuBarTransferRow(progress: progress)
                    }
                }

                Divider()
                    .padding(.top, 4)
            }

            // Nearby devices
            VStack(alignment: .leading, spacing: 4) {
                Text("Nearby Devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if appState.browser.discoveredPeers.isEmpty {
                    HStack {
                        if appState.browser.isSearching {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("No devices found")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                } else {
                    ForEach(appState.browser.discoveredPeers) { peer in
                        MenuBarPeerRow(peer: peer) {
                            appState.selectedPeerForSending = peer
                            appState.showFilePicker = true
                        }
                    }
                }
            }

            Divider()
                .padding(.top, 4)

            // Actions
            VStack(spacing: 0) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title.contains("CrossDrop") || $0.isKeyWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        // Open main window
                        NSApp.activate(ignoringOtherApps: true)
                    }
                } label: {
                    HStack {
                        Image(systemName: "macwindow")
                        Text("Open CrossDrop")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit CrossDrop")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280)
    }
}

struct MenuBarPeerRow: View {
    let peer: PeerDevice
    let onSend: () -> Void

    var body: some View {
        Button(action: onSend) {
            HStack(spacing: 8) {
                deviceIcon
                    .font(.body)
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(peer.alias)
                        .font(.body)
                        .lineLimit(1)
                    Text(peer.deviceType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.blue)
                    .font(.body)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var deviceIcon: some View {
        switch peer.deviceType.lowercased() {
        case "macos", "mac":
            Image(systemName: "desktopcomputer")
        case "android":
            Image(systemName: "smartphone")
        default:
            Image(systemName: "laptopcomputer")
        }
    }
}

struct MenuBarTransferRow: View {
    let progress: TransferProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(progress.direction == .incoming ? "From \(progress.peerAlias)" : "To \(progress.peerAlias)")
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress.overallFraction * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.overallFraction)
                .progressViewStyle(.linear)
                .scaleEffect(y: 0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
