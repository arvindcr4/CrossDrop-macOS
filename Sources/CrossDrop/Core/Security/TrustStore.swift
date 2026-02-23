import Foundation

/// Persists trusted device fingerprints using a TOFU (Trust On First Use) model.
/// Stores fingerprint-to-alias mappings in UserDefaults.
final class TrustStore {
    static let shared = TrustStore()

    private let defaultsKey = "com.crossdrop.trustedDevices"

    struct TrustedDevice: Codable {
        let fingerprint: String
        let alias: String
        let deviceType: String
        let firstSeen: Date
        var lastSeen: Date
    }

    private init() {}

    /// Returns all trusted devices.
    func trustedDevices() -> [TrustedDevice] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([TrustedDevice].self, from: data)) ?? []
    }

    /// Checks if a fingerprint is already trusted.
    func isTrusted(fingerprint: String) -> Bool {
        return trustedDevices().contains { $0.fingerprint == fingerprint }
    }

    /// Adds or updates a trusted device. Returns true if this is a new device (first use).
    @discardableResult
    func trustDevice(fingerprint: String, alias: String, deviceType: String) -> Bool {
        var devices = trustedDevices()
        let now = Date()

        if let index = devices.firstIndex(where: { $0.fingerprint == fingerprint }) {
            devices[index].lastSeen = now
            save(devices)
            return false // Already trusted
        } else {
            let device = TrustedDevice(
                fingerprint: fingerprint,
                alias: alias,
                deviceType: deviceType,
                firstSeen: now,
                lastSeen: now
            )
            devices.append(device)
            save(devices)
            return true // New trust
        }
    }

    /// Removes trust for a device by fingerprint.
    func removeTrust(fingerprint: String) {
        var devices = trustedDevices()
        devices.removeAll { $0.fingerprint == fingerprint }
        save(devices)
    }

    /// Removes all trusted devices.
    func removeAllTrust() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Returns the alias for a trusted fingerprint, if any.
    func alias(for fingerprint: String) -> String? {
        return trustedDevices().first { $0.fingerprint == fingerprint }?.alias
    }

    private func save(_ devices: [TrustedDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
