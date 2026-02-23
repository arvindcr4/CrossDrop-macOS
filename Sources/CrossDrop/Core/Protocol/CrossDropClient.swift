import Foundation

/// URLSession-based client for sending CrossDrop API requests to a peer.
final class CrossDropClient {
    private let session: URLSession
    private let baseURL: String
    private let bufferSize = 65536 // 64KB

    init(host: String, port: UInt16 = 48920) {
        self.baseURL = "https://\(host):\(port)/api/crossdrop/v1"
        self.session = TLSConfiguration.shared.createURLSession()
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// Register this device with the peer.
    func register(alias: String, deviceType: String, fingerprint: String) async throws -> RegisterResponse {
        let request = RegisterRequest(alias: alias, deviceType: deviceType, fingerprint: fingerprint)
        let body = try JSONEncoder().encode(request)
        return try await post(path: "/register", body: body)
    }

    /// Request to upload files.
    func prepareUpload(sessionId: String, files: [FileInfo]) async throws -> PrepareUploadResponse {
        let request = PrepareUploadRequest(sessionId: sessionId, files: files)
        let body = try JSONEncoder().encode(request)
        return try await post(path: "/prepare-upload", body: body)
    }

    /// Upload a single file, streaming in 64KB chunks.
    func uploadFile(
        sessionId: String,
        fileId: String,
        token: String,
        fileURL: URL,
        onProgress: @escaping (Int64) -> Void
    ) async throws -> UploadResponse {
        let path = "/upload?sessionId=\(sessionId.urlEncoded)&fileId=\(fileId.urlEncoded)&token=\(token.urlEncoded)"
        guard let url = URL(string: baseURL + path) else {
            throw CrossDropClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
        urlRequest.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

        // Read entire file for upload (URLSession handles the streaming internally)
        // For very large files, we use a stream-based approach
        let inputStream = InputStream(url: fileURL)!
        urlRequest.httpBodyStream = inputStream

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CrossDropClientError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        onProgress(fileSize)

        return try JSONDecoder().decode(UploadResponse.self, from: data)
    }

    /// Cancel a transfer session.
    func cancel(sessionId: String) async throws -> CancelResponse {
        let path = "/cancel?sessionId=\(sessionId.urlEncoded)"
        guard let url = URL(string: baseURL + path) else {
            throw CrossDropClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CrossDropClientError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try JSONDecoder().decode(CancelResponse.self, from: data)
    }

    // MARK: - Helpers

    private func post<T: Decodable>(path: String, body: Data) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw CrossDropClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CrossDropClientError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum CrossDropClientError: Error, LocalizedError {
    case invalidURL
    case serverError(Int)
    case connectionFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .serverError(let code): return "Server error: \(code)"
        case .connectionFailed: return "Connection failed"
        case .encodingFailed: return "Encoding failed"
        }
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
