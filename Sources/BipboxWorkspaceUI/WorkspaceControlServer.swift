// WorkspaceControlServer.swift — a minimal localhost HTTP/JSON control API that
// drives the LIVE workspace model. Intended for debug/automation only; the app
// decides whether to start it (gate behind #if DEBUG + an opt-in env var).
//
// Endpoints:
//   GET  /health            -> {"ok":true}
//   GET  /state             -> WorkspaceSnapshot JSON
//   POST /command  {json}   -> applies a WorkspaceCommand, returns WorkspaceSnapshot JSON
//
// Auth: if a token is set, requests must include `Authorization: Bearer <token>`.
import Foundation
import Network

@MainActor
public final class WorkspaceControlServer {
    private let model: WorkspaceModel
    private let port: NWEndpoint.Port
    private let token: String?
    private var listener: NWListener?

    public init(model: WorkspaceModel, port: UInt16 = 7777, token: String? = nil) {
        self.model = model
        self.port = NWEndpoint.Port(rawValue: port) ?? 7777
        self.token = token
    }

    public func start() {
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback   // 127.0.0.1 only
            let listener = try NWListener(using: params, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.handle(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
            NSLog("Bipbox control API listening on http://127.0.0.1:\(port.rawValue)")
        } catch {
            NSLog("Bipbox control API failed to start: \(error)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(buffer), request.isComplete {
                    let response = await self.respond(to: request)
                    self.send(response, on: connection)
                    return
                }
                if error != nil || isComplete {
                    connection.cancel()
                    return
                }
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest) async -> Data {
        if let token, request.bearerToken != token {
            return Self.httpResponse(status: "401 Unauthorized", json: Data(#"{"error":"unauthorized"}"#.utf8))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return Self.httpResponse(status: "200 OK", json: Data(#"{"ok":true}"#.utf8))
        case ("GET", "/state"), ("GET", "/snapshot"):
            let snap = await model.snapshot()
            return Self.httpResponse(status: "200 OK", json: (try? encoder.encode(snap)) ?? Data())
        case ("POST", "/command"):
            guard let command = try? JSONDecoder().decode(WorkspaceCommand.self, from: request.body) else {
                let snap = await model.snapshot(error: "Invalid command JSON")
                return Self.httpResponse(status: "400 Bad Request", json: (try? encoder.encode(snap)) ?? Data())
            }
            let snap = await model.apply(command)
            return Self.httpResponse(status: "200 OK", json: (try? encoder.encode(snap)) ?? Data())
        default:
            return Self.httpResponse(status: "404 Not Found", json: Data(#"{"error":"not found"}"#.utf8))
        }
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func httpResponse(status: String, json: Data) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(json.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(json)
        return data
    }
}

/// Tiny HTTP/1.1 request parser (enough for localhost JSON control).
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    let isComplete: Bool

    var bearerToken: String? {
        guard let auth = headers["authorization"], auth.lowercased().hasPrefix("bearer ") else { return nil }
        return String(auth.dropFirst(7))
    }

    init?(_ buffer: Data) {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        path = String(parts[1]).components(separatedBy: "?").first ?? String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        self.headers = headers

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = headerEnd.upperBound
        let available = buffer[bodyStart...]
        if available.count >= contentLength {
            body = Data(available.prefix(contentLength))
            isComplete = true
        } else {
            body = Data()
            isComplete = false
        }
    }
}
