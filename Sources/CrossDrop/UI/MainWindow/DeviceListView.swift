import SwiftUI
import UniformTypeIdentifiers

/// Displays discovered peer devices with drag-and-drop file sending support.
struct DeviceListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            if appState.browser.discoveredPeers.isEmpty {
                emptyState
            } else {
                peerList
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            Text("Nearby Devices")
                .font(.headline)
            Spacer()
            if appState.browser.isSearching {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No devices found")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Make sure CrossDrop is running on nearby devices")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    @ViewBuilder
    private var peerList: some View {
        List(appState.browser.discoveredPeers, selection: Binding(
            get: { appState.selectedPeerForSending?.id },
            set: { id in
                appState.selectedPeerForSending = appState.browser.discoveredPeers.first { $0.id == id }
            }
        )) { peer in
            PeerRow(peer: peer)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers, peer: peer)
                    return true
                }
                .tag(peer.id)
        }
        .listStyle(.sidebar)
    }

    private func handleDrop(providers: [NSItemProvider], peer: PeerDevice) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    urls.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            appState.sendFiles(to: peer, urls: urls)
        }
    }
}

struct PeerRow: View {
    let peer: PeerDevice

    var body: some View {
        HStack(spacing: 12) {
            deviceIcon
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.alias)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(peer.deviceType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if TrustStore.shared.isTrusted(fingerprint: peer.fingerprint) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .help("Trusted device")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var deviceIcon: some View {
        switch peer.deviceType.lowercased() {
        case "macos", "mac":
            Image(systemName: "desktopcomputer")
        case "ios", "iphone":
            Image(systemName: "iphone")
        case "ipad":
            Image(systemName: "ipad")
        case "android":
            Image(systemName: "smartphone")
        case "windows":
            Image(systemName: "pc")
        case "linux":
            Image(systemName: "terminal")
        default:
            Image(systemName: "laptopcomputer")
        }
    }
}
