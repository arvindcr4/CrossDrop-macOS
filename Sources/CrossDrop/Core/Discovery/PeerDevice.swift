import Foundation
import Network

/// Represents a discovered peer device on the local network.
@Observable
final class PeerDevice: Identifiable, Hashable {
    let id: String
    var alias: String
    var deviceType: String
    var fingerprint: String
    var endpoint: NWEndpoint?
    var host: String?
    var port: UInt16
    var lastSeen: Date

    init(
        id: String = UUID().uuidString,
        alias: String,
        deviceType: String,
        fingerprint: String,
        endpoint: NWEndpoint? = nil,
        host: String? = nil,
        port: UInt16 = 48920,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.alias = alias
        self.deviceType = deviceType
        self.fingerprint = fingerprint
        self.endpoint = endpoint
        self.host = host
        self.port = port
        self.lastSeen = lastSeen
    }

    static func == (lhs: PeerDevice, rhs: PeerDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
