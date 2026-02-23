import Foundation
import CryptoKit
import Network

/// Handles receiving uploaded file data, writing to disk, and verifying SHA-256 checksums.
final class FileReceiver {
    private let bufferSize = 65536 // 64KB

    /// Default download directory.
    var downloadDirectory: URL {
        let settingsDir = UserDefaults.standard.string(forKey: "downloadDirectory")
        if let settingsDir, !settingsDir.isEmpty {
            return URL(fileURLWithPath: settingsDir)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CrossDrop", isDirectory: true)
    }

    /// Receives a file from an NWConnection, streaming to disk with 64KB buffer.
    func receiveFile(
        fileInfo: FileInfo,
        initialData: Data?,
        expectedSize: Int64,
        connection: NWConnection,
        completion: @escaping (Result<(URL, Bool), Error>) -> Void
    ) {
        let destDir = downloadDirectory
        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        let destURL = uniqueFileURL(directory: destDir, fileName: fileInfo.name)

        guard FileManager.default.createFile(atPath: destURL.path, contents: nil) else {
            completion(.failure(FileReceiverError.cannotCreateFile))
            return
        }

        guard let fileHandle = try? FileHandle(forWritingTo: destURL) else {
            completion(.failure(FileReceiverError.cannotCreateFile))
            return
        }

        var hasher = SHA256()
        var totalReceived: Int64 = 0

        // Write initial data if present
        if let initialData, !initialData.isEmpty {
            fileHandle.write(initialData)
            hasher.update(data: initialData)
            totalReceived += Int64(initialData.count)
        }

        if totalReceived >= expectedSize {
            // All data received in initial chunk
            try? fileHandle.close()
            let digest = hasher.finalize()
            let hash = digest.map { String(format: "%02x", $0) }.joined()
            let sha256Match = hash == fileInfo.sha256
            completion(.success((destURL, sha256Match)))
            return
        }

        // Continue reading from connection
        readNextChunk(
            connection: connection,
            fileHandle: fileHandle,
            hasher: &hasher,
            totalReceived: totalReceived,
            expectedSize: expectedSize,
            fileInfo: fileInfo,
            destURL: destURL,
            completion: completion
        )
    }

    private func readNextChunk(
        connection: NWConnection,
        fileHandle: FileHandle,
        hasher: inout SHA256,
        totalReceived: Int64,
        expectedSize: Int64,
        fileInfo: FileInfo,
        destURL: URL,
        completion: @escaping (Result<(URL, Bool), Error>) -> Void
    ) {
        // Capture hasher as a mutable copy for the closure
        var mutableHasher = hasher
        var mutableReceived = totalReceived

        func readLoop() {
            let remaining = expectedSize - mutableReceived
            let readSize = min(Int(remaining), bufferSize)

            connection.receive(minimumIncompleteLength: 1, maximumLength: readSize) { data, _, isComplete, error in
                if let error = error {
                    try? fileHandle.close()
                    completion(.failure(error))
                    return
                }

                if let data = data, !data.isEmpty {
                    fileHandle.write(data)
                    mutableHasher.update(data: data)
                    mutableReceived += Int64(data.count)
                }

                if mutableReceived >= expectedSize || isComplete {
                    try? fileHandle.close()
                    let digest = mutableHasher.finalize()
                    let hash = digest.map { String(format: "%02x", $0) }.joined()
                    let sha256Match = hash == fileInfo.sha256
                    completion(.success((destURL, sha256Match)))
                    return
                }

                readLoop()
            }
        }

        readLoop()
    }

    /// Generates a unique filename to avoid overwriting existing files.
    private func uniqueFileURL(directory: URL, fileName: String) -> URL {
        var url = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 1

        repeat {
            let newName = ext.isEmpty ? "\(name) (\(counter))" : "\(name) (\(counter)).\(ext)"
            url = directory.appendingPathComponent(newName)
            counter += 1
        } while FileManager.default.fileExists(atPath: url.path)

        return url
    }
}

enum FileReceiverError: Error, LocalizedError {
    case cannotCreateFile
    case writeFailed
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile: return "Cannot create destination file"
        case .writeFailed: return "Failed to write file data"
        case .checksumMismatch: return "File checksum does not match"
        }
    }
}
