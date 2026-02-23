import SwiftUI

@main
struct CrossDropApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appState)
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)

        MenuBarExtra("CrossDrop", systemImage: "arrow.up.arrow.down.circle.fill") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

/// Central application state managing all CrossDrop services.
@Observable
final class AppState {
    // Services
    let server = CrossDropServer()
    let browser = ServiceBrowser()
    var advertiser: ServiceAdvertiser?
    let fileSender = FileSender()

    // State
    var deviceAlias: String {
        didSet {
            UserDefaults.standard.set(deviceAlias, forKey: "deviceAlias")
            advertiser?.alias = deviceAlias
            advertiser?.updateTXTRecord()
        }
    }
    var fingerprint: String = ""
    var isRunning: Bool = false

    // Transfer state
    var activeTransfers: [TransferProgress] = []
    var transferHistory: [TransferRecord] = []

    // Incoming transfer alerts
    var pendingIncomingTransfer: IncomingTransferInfo?
    var showIncomingAlert: Bool = false

    // Send file state
    var showFilePicker: Bool = false
    var selectedPeerForSending: PeerDevice?

    // Settings
    var downloadDirectory: String {
        didSet {
            UserDefaults.standard.set(downloadDirectory, forKey: "downloadDirectory")
        }
    }
    var autoAcceptFromTrusted: Bool {
        didSet {
            UserDefaults.standard.set(autoAcceptFromTrusted, forKey: "autoAcceptFromTrusted")
        }
    }

    struct IncomingTransferInfo: Identifiable {
        let id: String // sessionId
        let alias: String
        let deviceType: String
        let files: [FileInfo]
    }

    init() {
        self.deviceAlias = UserDefaults.standard.string(forKey: "deviceAlias")
            ?? Host.current().localizedName
            ?? "My Mac"
        self.downloadDirectory = UserDefaults.standard.string(forKey: "downloadDirectory") ?? ""
        self.autoAcceptFromTrusted = UserDefaults.standard.bool(forKey: "autoAcceptFromTrusted")

        setupServer()
        start()
    }

    func start() {
        do {
            fingerprint = try CertificateManager.shared.getFingerprint()

            // Start server
            try server.start()

            // Start advertising
            advertiser = ServiceAdvertiser(alias: deviceAlias)
            try advertiser?.start()

            // Start browsing
            browser.start()

            isRunning = true
        } catch {
            print("[CrossDrop] Failed to start: \(error)")
        }
    }

    func stop() {
        server.stop()
        advertiser?.stop()
        browser.stop()
        isRunning = false
    }

    private func setupServer() {
        server.onIncomingTransfer = { [weak self] sessionId, alias, deviceType, files in
            guard let self else { return }

            // Auto-accept if setting is enabled and device is trusted
            if self.autoAcceptFromTrusted {
                // Check if any trusted device matches the alias
                let trusted = TrustStore.shared.trustedDevices()
                if trusted.contains(where: { $0.alias == alias }) {
                    self.server.acceptTransfer(sessionId: sessionId)

                    let progress = TransferProgress(
                        sessionId: sessionId,
                        peerAlias: alias,
                        direction: .incoming,
                        files: files
                    )
                    progress.status = .inProgress
                    self.activeTransfers.append(progress)
                    return
                }
            }

            self.pendingIncomingTransfer = IncomingTransferInfo(
                id: sessionId,
                alias: alias,
                deviceType: deviceType,
                files: files
            )
            self.showIncomingAlert = true
        }

        server.onTransferAccepted = { [weak self] sessionId, _ in
            guard let self else { return }
            if let progress = self.activeTransfers.first(where: { $0.sessionId == sessionId }) {
                progress.status = .inProgress
            }
        }

        server.onTransferRejected = { [weak self] sessionId in
            guard let self else { return }
            self.activeTransfers.removeAll { $0.sessionId == sessionId }
        }

        server.onFileReceived = { [weak self] sessionId, fileId, savedURL in
            guard let self else { return }
            if let progress = self.activeTransfers.first(where: { $0.sessionId == sessionId }) {
                progress.markFileComplete(fileId: fileId)

                // Check if all files received
                let allDone = progress.files.allSatisfy { file in
                    progress.fileProgress[file.id]?.completed == true
                }

                if allDone {
                    progress.markComplete()
                    self.addToHistory(progress: progress)
                    self.activeTransfers.removeAll { $0.sessionId == sessionId }
                }
            }
        }

        server.onTransferCancelled = { [weak self] sessionId in
            guard let self else { return }
            if let progress = self.activeTransfers.first(where: { $0.sessionId == sessionId }) {
                progress.markCancelled()
            }
            self.activeTransfers.removeAll { $0.sessionId == sessionId }
        }
    }

    func acceptIncomingTransfer() {
        guard let incoming = pendingIncomingTransfer else { return }

        let progress = TransferProgress(
            sessionId: incoming.id,
            peerAlias: incoming.alias,
            direction: .incoming,
            files: incoming.files
        )
        progress.status = .inProgress
        activeTransfers.append(progress)

        server.acceptTransfer(sessionId: incoming.id)
        pendingIncomingTransfer = nil
        showIncomingAlert = false
    }

    func rejectIncomingTransfer() {
        guard let incoming = pendingIncomingTransfer else { return }
        server.rejectTransfer(sessionId: incoming.id)
        pendingIncomingTransfer = nil
        showIncomingAlert = false
    }

    func sendFiles(to peer: PeerDevice, urls: [URL]) {
        let progress = TransferProgress(
            sessionId: UUID().uuidString,
            peerAlias: peer.alias,
            direction: .outgoing,
            files: urls.enumerated().map { index, url in
                let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
                let size = attrs[.size] as? Int64 ?? 0
                return FileInfo(
                    id: UUID().uuidString,
                    name: url.lastPathComponent,
                    size: size,
                    mimeType: "application/octet-stream",
                    sha256: ""
                )
            }
        )
        activeTransfers.append(progress)

        Task {
            do {
                // Resolve peer host if needed
                if peer.host == nil {
                    let resolvedPeer = await resolvePeer(peer)
                    try await fileSender.sendFiles(
                        to: resolvedPeer,
                        fileURLs: urls,
                        alias: deviceAlias,
                        fingerprint: fingerprint,
                        progress: progress
                    )
                } else {
                    try await fileSender.sendFiles(
                        to: peer,
                        fileURLs: urls,
                        alias: deviceAlias,
                        fingerprint: fingerprint,
                        progress: progress
                    )
                }

                await MainActor.run {
                    self.addToHistory(progress: progress)
                    self.activeTransfers.removeAll { $0.id == progress.id }
                }
            } catch {
                await MainActor.run {
                    progress.markFailed(error: error.localizedDescription)
                }
            }
        }
    }

    private func resolvePeer(_ peer: PeerDevice) async -> PeerDevice {
        await withCheckedContinuation { continuation in
            browser.resolve(peer) { host, port in
                if let host {
                    peer.host = host
                    if let port {
                        peer.port = port
                    }
                }
                continuation.resume(returning: peer)
            }
        }
    }

    private func addToHistory(progress: TransferProgress) {
        let record = TransferRecord(
            id: progress.sessionId,
            peerAlias: progress.peerAlias,
            peerDeviceType: "",
            direction: progress.direction,
            files: progress.files,
            timestamp: Date(),
            status: progress.status
        )
        transferHistory.insert(record, at: 0)

        // Keep only last 100 records
        if transferHistory.count > 100 {
            transferHistory = Array(transferHistory.prefix(100))
        }
    }
}
