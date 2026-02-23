import Foundation

/// Tracks progress of a file transfer session.
@Observable
final class TransferProgress: Identifiable {
    let id: String
    let sessionId: String
    let peerAlias: String
    let direction: TransferRecord.TransferDirection
    let files: [FileInfo]

    var currentFileIndex: Int = 0
    var bytesTransferred: Int64 = 0
    var totalBytes: Int64 = 0
    var status: TransferRecord.TransferStatus = .pending
    var errorMessage: String?

    /// Per-file progress tracking.
    var fileProgress: [String: FileProgress] = [:]

    init(sessionId: String, peerAlias: String, direction: TransferRecord.TransferDirection, files: [FileInfo]) {
        self.id = sessionId
        self.sessionId = sessionId
        self.peerAlias = peerAlias
        self.direction = direction
        self.files = files
        self.totalBytes = files.reduce(0) { $0 + $1.size }
        for file in files {
            fileProgress[file.id] = FileProgress(fileId: file.id, fileName: file.name, totalBytes: file.size)
        }
    }

    var overallFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }

    var currentFileName: String? {
        guard currentFileIndex < files.count else { return nil }
        return files[currentFileIndex].name
    }

    var isComplete: Bool {
        status == .completed
    }

    var isFailed: Bool {
        status == .failed
    }

    func updateFileProgress(fileId: String, bytes: Int64) {
        if let fp = fileProgress[fileId] {
            let delta = bytes - fp.bytesTransferred
            fp.bytesTransferred = bytes
            bytesTransferred += delta
        }
    }

    func markFileComplete(fileId: String) {
        fileProgress[fileId]?.completed = true
        currentFileIndex += 1
    }

    func markComplete() {
        status = .completed
    }

    func markFailed(error: String) {
        status = .failed
        errorMessage = error
    }

    func markCancelled() {
        status = .cancelled
    }
}

/// Progress for a single file within a transfer.
@Observable
final class FileProgress: Identifiable {
    let id: String
    let fileId: String
    let fileName: String
    let totalBytes: Int64
    var bytesTransferred: Int64 = 0
    var completed: Bool = false

    init(fileId: String, fileName: String, totalBytes: Int64) {
        self.id = fileId
        self.fileId = fileId
        self.fileName = fileName
        self.totalBytes = totalBytes
    }

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }
}
