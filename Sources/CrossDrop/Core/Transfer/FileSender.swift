import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// Orchestrates sending files to a remote peer.
/// Handles: register -> prepare-upload -> upload per file.
final class FileSender {
    private let bufferSize = 65536 // 64KB

    /// Sends files to a peer device.
    func sendFiles(
        to peer: PeerDevice,
        fileURLs: [URL],
        alias: String,
        fingerprint: String,
        progress: TransferProgress
    ) async throws {
        guard let host = peer.host else {
            throw FileSenderError.noHostResolved
        }

        let client = CrossDropClient(host: host, port: peer.port)

        progress.status = .inProgress

        // Step 1: Register
        let registerResponse = try await client.register(
            alias: alias,
            deviceType: "macOS",
            fingerprint: fingerprint
        )
        let sessionId = registerResponse.sessionId

        // Step 2: Build file metadata
        var fileInfos: [FileInfo] = []
        var fileURLMap: [String: URL] = [:]

        for fileURL in fileURLs {
            let fileId = UUID().uuidString
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = attrs[.size] as? Int64 ?? 0
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let sha256 = try computeSHA256(fileURL: fileURL)

            let info = FileInfo(
                id: fileId,
                name: fileURL.lastPathComponent,
                size: size,
                mimeType: mimeType,
                sha256: sha256
            )
            fileInfos.append(info)
            fileURLMap[fileId] = fileURL
        }

        // Step 3: Prepare upload
        let prepareResponse = try await client.prepareUpload(sessionId: sessionId, files: fileInfos)

        guard prepareResponse.accepted else {
            progress.markFailed(error: "Transfer was rejected by the recipient")
            throw FileSenderError.transferRejected
        }

        let token = prepareResponse.token

        // Step 4: Upload each file
        for (index, fileInfo) in fileInfos.enumerated() {
            guard let fileURL = fileURLMap[fileInfo.id] else { continue }

            progress.currentFileIndex = index

            let uploadResponse = try await client.uploadFile(
                sessionId: sessionId,
                fileId: fileInfo.id,
                token: token,
                fileURL: fileURL
            ) { bytesWritten in
                progress.updateFileProgress(fileId: fileInfo.id, bytes: bytesWritten)
            }

            if !uploadResponse.success {
                progress.markFailed(error: "Upload failed for \(fileInfo.name)")
                throw FileSenderError.uploadFailed(fileInfo.name)
            }

            if !uploadResponse.sha256Match {
                progress.markFailed(error: "Checksum mismatch for \(fileInfo.name)")
                throw FileSenderError.checksumMismatch(fileInfo.name)
            }

            progress.markFileComplete(fileId: fileInfo.id)
        }

        progress.markComplete()
    }

    /// Cancels an active transfer session.
    func cancelTransfer(peer: PeerDevice, sessionId: String) async throws {
        guard let host = peer.host else { return }
        let client = CrossDropClient(host: host, port: peer.port)
        _ = try await client.cancel(sessionId: sessionId)
    }

    // MARK: - SHA-256

    private func computeSHA256(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum FileSenderError: Error, LocalizedError {
    case noHostResolved
    case transferRejected
    case uploadFailed(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .noHostResolved: return "Could not resolve peer address"
        case .transferRejected: return "Transfer was rejected"
        case .uploadFailed(let name): return "Upload failed for \(name)"
        case .checksumMismatch(let name): return "Checksum mismatch for \(name)"
        }
    }
}
