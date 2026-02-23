import Foundation
import Network
import Security

/// Configures TLS 1.3 options for NWListener and NWConnection using self-signed certificates with TOFU trust.
final class TLSConfiguration {
    static let shared = TLSConfiguration()

    private init() {}

    /// Creates TLS parameters for the server (NWListener).
    func serverTLSParameters() throws -> NWParameters {
        let identity = try CertificateManager.shared.getOrCreateIdentity()

        let tlsOptions = NWProtocolTLS.Options()

        let secIdentity = sec_identity_create(identity)!
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        // Custom verification: accept all peers (TOFU model - we verify fingerprints at the application layer)
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, sec_trust, completionHandler in
                completionHandler(true)
            },
            DispatchQueue.global(qos: .userInitiated)
        )

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = 30

        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.includePeerToPeer = true

        return parameters
    }

    /// Creates TLS parameters for connecting to a peer (NWConnection / URLSession).
    func clientTLSParameters() throws -> NWParameters {
        let identity = try CertificateManager.shared.getOrCreateIdentity()

        let tlsOptions = NWProtocolTLS.Options()

        let secIdentity = sec_identity_create(identity)!
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        // TOFU: accept self-signed certificates
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, sec_trust, completionHandler in
                completionHandler(true)
            },
            DispatchQueue.global(qos: .userInitiated)
        )

        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        parameters.includePeerToPeer = true

        return parameters
    }

    /// Creates a URLSession configured with TOFU trust for self-signed certs.
    func createURLSession(delegate: URLSessionDelegate? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let effectiveDelegate = delegate ?? TOFUSessionDelegate()
        return URLSession(configuration: config, delegate: effectiveDelegate, delegateQueue: nil)
    }
}

/// URLSession delegate that accepts self-signed certificates (TOFU model).
final class TOFUSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // TOFU: accept the server's certificate
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }
}
