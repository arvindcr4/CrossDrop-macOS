import Foundation
import Network

/// Embedded HTTPS server handling CrossDrop API endpoints via NWListener.
/// Implements a minimal HTTP/1.1 parser for incoming requests and routes them appropriately.
final class CrossDropServer {
    private var listener: NWListener?
    private let port: UInt16 = 48920
    private let queue = DispatchQueue(label: "com.crossdrop.server", attributes: .concurrent)

    private var activeSessions: [String: Session] = [:]
    private let sessionsLock = NSLock()

    var onIncomingTransfer: ((String, String, String, [FileInfo]) -> Void)? // sessionId, alias, deviceType, files
    var onTransferAccepted: ((String, String) -> Void)? // sessionId, token
    var onTransferRejected: ((String) -> Void)? // sessionId
    var onFileReceived: ((String, String, URL) -> Void)? // sessionId, fileId, savedURL
    var onTransferCancelled: ((String) -> Void)? // sessionId

    private var fileReceiver: FileReceiver?

    struct Session {
        let id: String
        let alias: String
        let deviceType: String
        let fingerprint: String
        var files: [FileInfo]
        var token: String?
        var accepted: Bool = false
        var cancelled: Bool = false
    }

    /// Pending accept/reject decisions keyed by sessionId.
    private var pendingDecisions: [String: ((Bool) -> Void)] = [:]
    private let decisionsLock = NSLock()

    init() {
        self.fileReceiver = FileReceiver()
    }

    func start() throws {
        let parameters = try TLSConfiguration.shared.serverTLSParameters()

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[CrossDropServer] Listening on port \(self.port)")
            case .failed(let error):
                print("[CrossDropServer] Failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Called by UI to accept an incoming transfer.
    func acceptTransfer(sessionId: String) {
        decisionsLock.lock()
        let callback = pendingDecisions.removeValue(forKey: sessionId)
        decisionsLock.unlock()
        callback?(true)
    }

    /// Called by UI to reject an incoming transfer.
    func rejectTransfer(sessionId: String) {
        decisionsLock.lock()
        let callback = pendingDecisions.removeValue(forKey: sessionId)
        decisionsLock.unlock()
        callback?(false)
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.readRequest(from: connection)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            self.parseAndRoute(data: data, connection: connection)
        }
    }

    // MARK: - HTTP Parsing & Routing

    private func parseAndRoute(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid request"])
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "Empty request"])
            return
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Malformed request line"])
            return
        }

        let method = String(parts[0])
        let fullPath = String(parts[1])

        // Parse path and query parameters
        let pathComponents = fullPath.split(separator: "?", maxSplits: 1)
        let path = String(pathComponents[0])
        var queryParams: [String: String] = [:]
        if pathComponents.count > 1 {
            let queryString = String(pathComponents[1])
            for param in queryString.split(separator: "&") {
                let kv = param.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    queryParams[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
        }

        // Extract body (after \r\n\r\n)
        var bodyData: Data?
        if let range = data.range(of: Data("\r\n\r\n".utf8)) {
            let bodyStart = range.upperBound
            if bodyStart < data.count {
                bodyData = data.subdata(in: bodyStart..<data.count)
            }
        }

        // Also check Content-Length to see if we need more data
        var contentLength = 0
        for line in lines {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        guard method == "POST" else {
            sendResponse(connection: connection, status: 405, body: ["error": "Method not allowed"])
            return
        }

        // Route
        switch path {
        case "/api/crossdrop/v1/register":
            handleRegister(body: bodyData, connection: connection)

        case "/api/crossdrop/v1/prepare-upload":
            handlePrepareUpload(body: bodyData, connection: connection)

        case "/api/crossdrop/v1/upload":
            handleUpload(queryParams: queryParams, initialBody: bodyData, contentLength: contentLength, connection: connection)

        case "/api/crossdrop/v1/cancel":
            handleCancel(queryParams: queryParams, connection: connection)

        default:
            sendResponse(connection: connection, status: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Route Handlers

    private func handleRegister(body: Data?, connection: NWConnection) {
        guard let body = body,
              let request = try? JSONDecoder().decode(RegisterRequest.self, from: body) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid register request"])
            return
        }

        let sessionId = UUID().uuidString

        sessionsLock.lock()
        activeSessions[sessionId] = Session(
            id: sessionId,
            alias: request.alias,
            deviceType: request.deviceType,
            fingerprint: request.fingerprint,
            files: []
        )
        sessionsLock.unlock()

        // Trust the device (TOFU)
        TrustStore.shared.trustDevice(
            fingerprint: request.fingerprint,
            alias: request.alias,
            deviceType: request.deviceType
        )

        let response = RegisterResponse(sessionId: sessionId)
        sendCodableResponse(connection: connection, status: 200, response: response)
    }

    private func handlePrepareUpload(body: Data?, connection: NWConnection) {
        guard let body = body,
              let request = try? JSONDecoder().decode(PrepareUploadRequest.self, from: body) else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid prepare-upload request"])
            return
        }

        sessionsLock.lock()
        guard var session = activeSessions[request.sessionId] else {
            sessionsLock.unlock()
            sendResponse(connection: connection, status: 404, body: ["error": "Session not found"])
            return
        }
        session.files = request.files
        activeSessions[request.sessionId] = session
        sessionsLock.unlock()

        // Notify the UI about the incoming transfer and wait for accept/reject
        let sessionId = request.sessionId

        DispatchQueue.main.async { [weak self] in
            self?.onIncomingTransfer?(sessionId, session.alias, session.deviceType, request.files)
        }

        // Wait for the user's decision with a timeout
        let semaphore = DispatchSemaphore(value: 0)
        var accepted = false

        decisionsLock.lock()
        pendingDecisions[sessionId] = { decision in
            accepted = decision
            semaphore.signal()
        }
        decisionsLock.unlock()

        // Wait up to 60 seconds for user decision
        let result = semaphore.wait(timeout: .now() + 60)

        if result == .timedOut {
            accepted = false
            decisionsLock.lock()
            pendingDecisions.removeValue(forKey: sessionId)
            decisionsLock.unlock()
        }

        if accepted {
            let token = UUID().uuidString
            sessionsLock.lock()
            activeSessions[sessionId]?.token = token
            activeSessions[sessionId]?.accepted = true
            sessionsLock.unlock()

            let response = PrepareUploadResponse(accepted: true, token: token, rejectedFiles: [])
            sendCodableResponse(connection: connection, status: 200, response: response)

            DispatchQueue.main.async { [weak self] in
                self?.onTransferAccepted?(sessionId, token)
            }
        } else {
            let response = PrepareUploadResponse(accepted: false, token: "", rejectedFiles: request.files.map { $0.id })
            sendCodableResponse(connection: connection, status: 200, response: response)

            DispatchQueue.main.async { [weak self] in
                self?.onTransferRejected?(sessionId)
            }
        }
    }

    private func handleUpload(queryParams: [String: String], initialBody: Data?, contentLength: Int, connection: NWConnection) {
        guard let sessionId = queryParams["sessionId"],
              let fileId = queryParams["fileId"],
              let token = queryParams["token"] else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing query parameters"])
            return
        }

        sessionsLock.lock()
        guard let session = activeSessions[sessionId],
              session.accepted,
              session.token == token else {
            sessionsLock.unlock()
            sendResponse(connection: connection, status: 403, body: ["error": "Invalid session or token"])
            return
        }

        guard let fileInfo = session.files.first(where: { $0.id == fileId }) else {
            sessionsLock.unlock()
            sendResponse(connection: connection, status: 404, body: ["error": "File not found in session"])
            return
        }
        sessionsLock.unlock()

        // Receive file data using streaming with 64KB buffer
        let receiver = fileReceiver ?? FileReceiver()

        receiver.receiveFile(
            fileInfo: fileInfo,
            initialData: initialBody,
            expectedSize: fileInfo.size,
            connection: connection
        ) { [weak self] result in
            switch result {
            case .success(let (savedURL, sha256Match)):
                let response = UploadResponse(success: true, sha256Match: sha256Match)
                self?.sendCodableResponse(connection: connection, status: 200, response: response)

                DispatchQueue.main.async {
                    self?.onFileReceived?(sessionId, fileId, savedURL)
                }

            case .failure(let error):
                let response = UploadResponse(success: false, sha256Match: false)
                self?.sendCodableResponse(connection: connection, status: 500, response: response)
                print("[CrossDropServer] Upload failed: \(error)")
            }
        }
    }

    private func handleCancel(queryParams: [String: String], connection: NWConnection) {
        guard let sessionId = queryParams["sessionId"] else {
            sendResponse(connection: connection, status: 400, body: ["error": "Missing sessionId"])
            return
        }

        sessionsLock.lock()
        activeSessions[sessionId]?.cancelled = true
        activeSessions.removeValue(forKey: sessionId)
        sessionsLock.unlock()

        // Also cancel any pending decisions
        decisionsLock.lock()
        let callback = pendingDecisions.removeValue(forKey: sessionId)
        decisionsLock.unlock()
        callback?(false)

        let response = CancelResponse(cancelled: true)
        sendCodableResponse(connection: connection, status: 200, response: response)

        DispatchQueue.main.async { [weak self] in
            self?.onTransferCancelled?(sessionId)
        }
    }

    // MARK: - Response Helpers

    private func sendCodableResponse<T: Encodable>(connection: NWConnection, status: Int, response: T) {
        guard let jsonData = try? JSONEncoder().encode(response) else {
            sendResponse(connection: connection, status: 500, body: ["error": "Encoding failed"])
            return
        }

        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data(header.utf8)
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendResponse(connection: NWConnection, status: Int, body: [String: String]) {
        let jsonData = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data(header.utf8)
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Removes a completed session.
    func cleanupSession(_ sessionId: String) {
        sessionsLock.lock()
        activeSessions.removeValue(forKey: sessionId)
        sessionsLock.unlock()
    }
}
