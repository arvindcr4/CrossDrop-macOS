import SwiftUI

/// Main window with a split view: device list on the left, transfer history on the right.
struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            DeviceListView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            TransferHistoryView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                statusIndicator

                Button {
                    appState.showFilePicker = true
                } label: {
                    Label("Send Files", systemImage: "square.and.arrow.up")
                }
                .disabled(appState.selectedPeerForSending == nil)
                .help("Send files to selected device")
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showIncomingAlert },
            set: { appState.showIncomingAlert = $0 }
        )) {
            if let incoming = appState.pendingIncomingTransfer {
                IncomingTransferAlert(transfer: incoming)
                    .environment(appState)
            }
        }
        .sheet(item: Binding(
            get: { appState.activeTransfers.first { $0.status == .inProgress } },
            set: { _ in }
        )) { progress in
            TransferProgressSheet(progress: progress)
                .environment(appState)
        }
        .fileImporter(
            isPresented: Binding(
                get: { appState.showFilePicker },
                set: { appState.showFilePicker = $0 }
            ),
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(appState.isRunning ? "Active" : "Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let peer = appState.selectedPeerForSending else { return }
            let accessingURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
            appState.sendFiles(to: peer, urls: accessingURLs)
            // Stop accessing after a delay to let the transfer start
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for url in accessingURLs {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        case .failure(let error):
            print("[CrossDrop] File picker error: \(error)")
        }
    }
}
