import Foundation
import Network

/// Advertises this device as a CrossDrop peer via Bonjour/mDNS.
final class ServiceAdvertiser {
    private var listener: NWListener?
    private let port: UInt16 = 48920
    private let serviceType = "_crossdrop._tcp."

    var alias: String
    var deviceType: String = "macOS"
    var fingerprint: String = ""

    var onReady: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(alias: String) {
        self.alias = alias
    }

    func start() throws {
        fingerprint = try CertificateManager.shared.getFingerprint()

        let parameters = try TLSConfiguration.shared.serverTLSParameters()

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

        let txtRecord = NWTXTRecord([
            "alias": alias,
            "dtype": deviceType,
            "fp": String(fingerprint.prefix(32)) // TXT records have size limits
        ])

        listener?.service = NWListener.Service(
            name: alias,
            type: serviceType,
            txtRecord: txtRecord
        )

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onReady?()
            case .failed(let error):
                self?.onError?(error)
            default:
                break
            }
        }

        listener?.newConnectionHandler = { _ in
            // Connections to port 48920 for the HTTP server are handled by CrossDropServer.
            // This listener is only used for Bonjour advertisement.
        }

        listener?.start(queue: DispatchQueue(label: "com.crossdrop.advertiser"))
    }

    func updateTXTRecord() {
        let txtRecord = NWTXTRecord([
            "alias": alias,
            "dtype": deviceType,
            "fp": String(fingerprint.prefix(32))
        ])
        listener?.service = NWListener.Service(
            name: alias,
            type: serviceType,
            txtRecord: txtRecord
        )
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
