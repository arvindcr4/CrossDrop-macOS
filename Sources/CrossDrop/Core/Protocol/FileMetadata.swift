import Foundation

/// Registration request sent when connecting to a peer.
struct RegisterRequest: Codable {
    let alias: String
    let deviceType: String
    let fingerprint: String
}

/// Registration response with session ID.
struct RegisterResponse: Codable {
    let sessionId: String
}

/// Information about a single file to transfer.
struct FileInfo: Codable, Identifiable {
    let id: String
    let name: String
    let size: Int64
    let mimeType: String
    let sha256: String
}

/// Request to prepare for an upload session.
struct PrepareUploadRequest: Codable {
    let sessionId: String
    let files: [FileInfo]
}

/// Response to a prepare-upload request.
struct PrepareUploadResponse: Codable {
    let accepted: Bool
    let token: String
    let rejectedFiles: [String]
}

/// Response after a file upload completes.
struct UploadResponse: Codable {
    let success: Bool
    let sha256Match: Bool
}

/// Response to a cancel request.
struct CancelResponse: Codable {
    let cancelled: Bool
}

/// Represents a completed or active transfer record.
struct TransferRecord: Identifiable, Codable {
    let id: String
    let peerAlias: String
    let peerDeviceType: String
    let direction: TransferDirection
    let files: [FileInfo]
    let timestamp: Date
    var status: TransferStatus

    enum TransferDirection: String, Codable {
        case incoming
        case outgoing
    }

    enum TransferStatus: String, Codable {
        case pending
        case inProgress
        case completed
        case failed
        case cancelled
    }
}
