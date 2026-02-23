import SwiftUI

/// Settings view for configuring device name, download folder, and trust settings.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showFolderPicker = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            securitySettings
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }

            aboutView
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 360)
    }

    @ViewBuilder
    private var generalSettings: some View {
        Form {
            Section("Device") {
                @Bindable var state = appState
                TextField("Device Name", text: $state.deviceAlias)
                    .textFieldStyle(.roundedBorder)

                LabeledContent("Device Type") {
                    Text("macOS")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Downloads") {
                HStack {
                    LabeledContent("Save files to") {
                        Text(downloadDisplayPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose...") {
                        chooseDownloadFolder()
                    }
                }

                @Bindable var state2 = appState
                Toggle("Auto-accept from trusted devices", isOn: $state2.autoAcceptFromTrusted)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var securitySettings: some View {
        Form {
            Section("Identity") {
                LabeledContent("Fingerprint") {
                    Text(appState.fingerprint.isEmpty ? "Not generated" : appState.fingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }

            Section("Trusted Devices") {
                let trustedDevices = TrustStore.shared.trustedDevices()

                if trustedDevices.isEmpty {
                    Text("No trusted devices")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(trustedDevices, id: \.fingerprint) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.alias)
                                    .font(.body)
                                Text(device.deviceType)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Trusted since \(device.firstSeen.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Remove") {
                                TrustStore.shared.removeTrust(fingerprint: device.fingerprint)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .font(.caption)
                        }
                    }
                }

                if !trustedDevices.isEmpty {
                    Button("Remove All Trusted Devices") {
                        TrustStore.shared.removeAllTrust()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private var aboutView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("CrossDrop")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Cross-platform local file sharing")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            VStack(spacing: 4) {
                Text("Protocol: CrossDrop v1")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Port: 48920 | TLS 1.3 | ECDSA P-256")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private var downloadDisplayPath: String {
        if appState.downloadDirectory.isEmpty {
            return "~/Downloads/CrossDrop"
        }
        return appState.downloadDirectory.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where to save received files"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.downloadDirectory = url.path
            }
        }
    }
}
