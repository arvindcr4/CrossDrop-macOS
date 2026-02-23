import Foundation
import Network

/// Browses for CrossDrop peers on the local network using Bonjour/mDNS.
@Observable
final class ServiceBrowser {
    private var browser: NWBrowser?
    private let serviceType = "_crossdrop._tcp."

    var discoveredPeers: [PeerDevice] = []
    var isSearching: Bool = false

    func start() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: descriptor, using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleResultsChanged(results)
        }

        browser?.start(queue: DispatchQueue(label: "com.crossdrop.browser"))
    }

    func stop() {
        browser?.cancel()
        browser = nil
        DispatchQueue.main.async {
            self.isSearching = false
        }
    }

    private func handleResultsChanged(_ results: Set<NWBrowser.Result>) {
        var peers: [PeerDevice] = []

        for result in results {
            guard case .service(let name, let type, _, _) = result.endpoint else { continue }
            guard type == serviceType else { continue }

            var alias = name
            var deviceType = "unknown"
            var fingerprint = ""

            if case .bonjour(let txtRecord) = result.metadata {
                if let a = txtRecord["alias"] { alias = a }
                if let d = txtRecord["dtype"] { deviceType = d }
                if let f = txtRecord["fp"] { fingerprint = f }
            }

            let peer = PeerDevice(
                id: "\(name).\(type)",
                alias: alias,
                deviceType: deviceType,
                fingerprint: fingerprint,
                endpoint: result.endpoint
            )

            peers.append(peer)
        }

        DispatchQueue.main.async {
            self.discoveredPeers = peers
        }
    }

    /// Resolves a peer's endpoint to get host and port for connecting.
    func resolve(_ peer: PeerDevice, completion: @escaping (String?, UInt16?) -> Void) {
        guard let endpoint = peer.endpoint else {
            completion(nil, nil)
            return
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = innerEndpoint {
                    let hostStr: String
                    switch host {
                    case .ipv4(let addr):
                        hostStr = "\(addr)"
                    case .ipv6(let addr):
                        hostStr = "\(addr)"
                    case .name(let name, _):
                        hostStr = name
                    @unknown default:
                        hostStr = "\(host)"
                    }
                    connection.cancel()
                    completion(hostStr, port.rawValue)
                }
            case .failed, .cancelled:
                completion(nil, nil)
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "com.crossdrop.resolve"))
    }
}
