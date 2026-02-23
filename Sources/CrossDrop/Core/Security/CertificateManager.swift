import Foundation
import Security
import CryptoKit

/// Manages ECDSA P-256 self-signed certificate generation, Keychain storage, and retrieval.
final class CertificateManager {
    static let shared = CertificateManager()

    private let keychainLabel = "com.crossdrop.identity"
    private let keychainTag = "com.crossdrop.key".data(using: .utf8)!

    private var cachedIdentity: SecIdentity?
    private var cachedFingerprint: String?

    private init() {}

    /// Returns the device's TLS identity, creating one if it doesn't exist.
    func getOrCreateIdentity() throws -> SecIdentity {
        if let cached = cachedIdentity {
            return cached
        }

        if let existing = try loadIdentityFromKeychain() {
            cachedIdentity = existing
            return existing
        }

        let identity = try generateSelfSignedIdentity()
        cachedIdentity = identity
        return identity
    }

    /// Returns the SHA-256 fingerprint of the device's certificate.
    func getFingerprint() throws -> String {
        if let cached = cachedFingerprint {
            return cached
        }

        let identity = try getOrCreateIdentity()
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        guard let cert = certRef else {
            throw CertificateError.fingerprintFailed
        }

        let certData = SecCertificateCopyData(cert) as Data
        let hash = SHA256.hash(data: certData)
        let fingerprint = hash.map { String(format: "%02x", $0) }.joined(separator: ":")
        cachedFingerprint = fingerprint
        return fingerprint
    }

    /// Returns the certificate from the identity.
    func getCertificate() throws -> SecCertificate {
        let identity = try getOrCreateIdentity()
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        guard let cert = certRef else {
            throw CertificateError.certificateNotFound
        }
        return cert
    }

    // MARK: - Keychain Operations

    private func loadIdentityFromKeychain() throws -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keychainLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw CertificateError.keychainError(status)
        }

        return (item as! SecIdentity)
    }

    private func generateSelfSignedIdentity() throws -> SecIdentity {
        // Generate ECDSA P-256 key pair
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrApplicationTag as String: keychainTag,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &error) else {
            throw CertificateError.keyGenerationFailed(error?.takeRetainedValue().localizedDescription ?? "Unknown")
        }

        // Build self-signed certificate using ASN.1 DER encoding
        let certData = try buildSelfSignedCertificate(privateKey: privateKey)

        guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw CertificateError.certificateCreationFailed
        }

        // Store certificate in Keychain
        let addCertQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: keychainLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let addStatus = SecItemAdd(addCertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw CertificateError.keychainError(addStatus)
        }

        // Now retrieve the identity (private key + certificate pair)
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keychainLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var identityItem: CFTypeRef?
        let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityItem)

        guard identityStatus == errSecSuccess, let identity = identityItem else {
            throw CertificateError.identityNotFound
        }

        return (identity as! SecIdentity)
    }

    // MARK: - ASN.1 DER Certificate Building

    private func buildSelfSignedCertificate(privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CertificateError.keyGenerationFailed("Cannot derive public key")
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CertificateError.keyGenerationFailed("Cannot export public key")
        }

        let hostname = Host.current().localizedName ?? "CrossDrop-Mac"
        let now = Date()
        let oneYear: TimeInterval = 365 * 24 * 60 * 60

        // Build TBSCertificate
        var tbs = Data()

        // Version (v3 = 2)
        tbs.append(contentsOf: asn1Context(tag: 0, content: asn1Integer(value: 2)))

        // Serial number
        let serialBytes = withUnsafeBytes(of: UInt64.random(in: 1...UInt64.max).bigEndian) { Data($0) }
        tbs.append(contentsOf: asn1Integer(data: serialBytes))

        // Signature algorithm: ecdsaWithSHA256 (1.2.840.10045.4.3.2)
        tbs.append(contentsOf: asn1Sequence(content: asn1OID([1, 2, 840, 10045, 4, 3, 2])))

        // Issuer: CN=<hostname>
        tbs.append(contentsOf: asn1Sequence(content:
            asn1Set(content:
                asn1Sequence(content:
                    asn1OID([2, 5, 4, 3]) + asn1UTF8String(hostname)
                )
            )
        ))

        // Validity
        tbs.append(contentsOf: asn1Sequence(content:
            asn1UTCTime(now) + asn1UTCTime(now.addingTimeInterval(oneYear))
        ))

        // Subject: same as issuer
        tbs.append(contentsOf: asn1Sequence(content:
            asn1Set(content:
                asn1Sequence(content:
                    asn1OID([2, 5, 4, 3]) + asn1UTF8String(hostname)
                )
            )
        ))

        // SubjectPublicKeyInfo for EC P-256
        let spki = asn1Sequence(content:
            asn1Sequence(content:
                asn1OID([1, 2, 840, 10045, 2, 1]) + // ecPublicKey
                asn1OID([1, 2, 840, 10045, 3, 1, 7])  // prime256v1
            ) +
            asn1BitString(publicKeyData)
        )
        tbs.append(contentsOf: spki)

        let tbsCertificate = asn1Sequence(content: tbs)

        // Sign the TBSCertificate
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            tbsCertificate as CFData,
            &error
        ) as Data? else {
            throw CertificateError.signingFailed
        }

        // Build full certificate
        let certificate = asn1Sequence(content:
            tbsCertificate +
            asn1Sequence(content: asn1OID([1, 2, 840, 10045, 4, 3, 2])) +
            asn1BitString(signature)
        )

        return certificate
    }

    // MARK: - ASN.1 Helpers

    private func asn1Length(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        } else if length < 256 {
            return Data([0x81, UInt8(length)])
        } else if length < 65536 {
            return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
        } else {
            return Data([0x83, UInt8(length >> 16), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        }
    }

    private func asn1Sequence(content: Data) -> Data {
        Data([0x30]) + asn1Length(content.count) + content
    }

    private func asn1Set(content: Data) -> Data {
        Data([0x31]) + asn1Length(content.count) + content
    }

    private func asn1Integer(value: Int) -> Data {
        var bytes = withUnsafeBytes(of: value.bigEndian) { Array($0) }
        while bytes.count > 1 && bytes[0] == 0 { bytes.removeFirst() }
        if bytes[0] & 0x80 != 0 { bytes.insert(0x00, at: 0) }
        let data = Data(bytes)
        return Data([0x02]) + asn1Length(data.count) + data
    }

    private func asn1Integer(data: Data) -> Data {
        var bytes = Array(data)
        while bytes.count > 1 && bytes[0] == 0 { bytes.removeFirst() }
        if bytes[0] & 0x80 != 0 { bytes.insert(0x00, at: 0) }
        let d = Data(bytes)
        return Data([0x02]) + asn1Length(d.count) + d
    }

    private func asn1OID(_ components: [UInt]) -> Data {
        var content = Data()
        if components.count >= 2 {
            content.append(UInt8(40 * components[0] + components[1]))
        }
        for i in 2..<components.count {
            content.append(contentsOf: encodeOIDComponent(components[i]))
        }
        return Data([0x06]) + asn1Length(content.count) + content
    }

    private func encodeOIDComponent(_ value: UInt) -> [UInt8] {
        if value < 128 {
            return [UInt8(value)]
        }
        var result: [UInt8] = []
        var v = value
        result.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            result.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return result
    }

    private func asn1UTF8String(_ string: String) -> Data {
        let data = Data(string.utf8)
        return Data([0x0C]) + asn1Length(data.count) + data
    }

    private func asn1BitString(_ data: Data) -> Data {
        let content = Data([0x00]) + data // 0 unused bits
        return Data([0x03]) + asn1Length(content.count) + content
    }

    private func asn1UTCTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let str = formatter.string(from: date)
        let data = Data(str.utf8)
        return Data([0x17]) + asn1Length(data.count) + data
    }

    private func asn1Context(tag: Int, content: Data) -> Data {
        Data([UInt8(0xA0 | tag)]) + asn1Length(content.count) + content
    }

    /// Deletes the stored identity from the Keychain (for testing/reset).
    func deleteIdentity() {
        let queries: [[String: Any]] = [
            [kSecClass as String: kSecClassIdentity, kSecAttrLabel as String: keychainLabel],
            [kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: keychainLabel],
            [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keychainTag]
        ]
        for query in queries {
            SecItemDelete(query as CFDictionary)
        }
        cachedIdentity = nil
        cachedFingerprint = nil
    }
}

enum CertificateError: Error, LocalizedError {
    case keyGenerationFailed(String)
    case certificateCreationFailed
    case signingFailed
    case keychainError(OSStatus)
    case certificateNotFound
    case fingerprintFailed
    case identityNotFound

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let msg): return "Key generation failed: \(msg)"
        case .certificateCreationFailed: return "Certificate creation failed"
        case .signingFailed: return "Certificate signing failed"
        case .keychainError(let status): return "Keychain error: \(status)"
        case .certificateNotFound: return "Certificate not found"
        case .fingerprintFailed: return "Failed to compute fingerprint"
        case .identityNotFound: return "Identity not found in Keychain"
        }
    }
}
