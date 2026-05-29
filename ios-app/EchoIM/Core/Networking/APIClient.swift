import Foundation

struct AuthenticatedUser: Codable, Equatable {
    let id: Int
    let username: String
    let email: String
    let displayName: String?
    let avatarUrl: String?

    /// 当前登录用户的 UI 展示名；displayName 为空白时回退到 username。
    var displayTitle: String {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDisplayName?.isEmpty == false ? trimmedDisplayName! : username
    }

    /// 仅当 displayName 是有效主标题时，才额外展示 @username。
    var usernameSubtitle: String? {
        displayTitle == username ? nil : "@\(username)"
    }
}

struct AuthResponse: Codable, Equatable {
    let token: String
    let user: AuthenticatedUser
}

struct EmptyResponse: Decodable, Equatable {}

private final class UploadTaskState: @unchecked Sendable {
    private let lock = NSLock()
    // 项目默认 MainActor 隔离；这些字段由 lock 保护，并且必须能在取消 handler 中同步访问。
    nonisolated(unsafe) private var observation: NSKeyValueObservation?
    nonisolated(unsafe) private var task: URLSessionUploadTask?
    nonisolated(unsafe) private var cancelled = false

    nonisolated func configure(task: URLSessionUploadTask, observation: NSKeyValueObservation) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            observation.invalidate()
            task.cancel()
            return false
        }

        self.task = task
        self.observation = observation
        lock.unlock()
        return true
    }

    nonisolated func invalidateObservation() {
        lock.lock()
        let observation = observation
        self.observation = nil
        lock.unlock()
        observation?.invalidate()
    }

    nonisolated func cancel() {
        lock.lock()
        cancelled = true
        let observation = observation
        let task = task
        self.observation = nil
        self.task = nil
        lock.unlock()

        observation?.invalidate()
        task?.cancel()
    }
}

@MainActor
final class APIClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = decodeISO8601Date(rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid ISO 8601: \(rawValue)"
            )
        }

        return decoder
    }()

    nonisolated static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 请求体默认保留 Swift 字段名；需要 snake_case 时由具体模型自己声明 CodingKeys。
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        token: String? = nil,
        body: Encodable? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Endpoints.baseURL)?.absoluteURL else {
            Log.error(.network, "✗ invalid URL \(method) \(path)")
            throw APIError.invalidResponse
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try Self.jsonEncoder.encode(AnyEncodable(body))
            } catch {
                Log.error(.network, "✗ encode \(method) \(path): \(error.localizedDescription)")
                throw error
            }
        }

        #if DEBUG
        if let httpBody = req.httpBody {
            Log.info(.network, "→ \(method) \(path) body: \(Self.redactedBody(httpBody))")
        } else {
            Log.info(.network, "→ \(method) \(path)")
        }
        #else
        Log.info(.network, "→ \(method) \(path)")
        #endif

        return try await execute(req, method: method, path: path)
    }

    func execute<Response: Decodable>(
        _ urlRequest: URLRequest,
        method: String,
        path: String
    ) async throws -> Response {
        let start = Date()
        let (data, response) = try await performTransport(
            method: method,
            path: path,
            start: start
        ) {
            try await session.data(for: urlRequest)
        }

        return try decodeResponse(
            data: data,
            response: response,
            method: method,
            path: path,
            start: start
        )
    }

    func executeUploadWithProgress<Response: Decodable>(
        _ request: URLRequest,
        method: String,
        path: String,
        body: Data,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Response {
        let start = Date()
        let (data, response) = try await performTransport(
            method: method,
            path: path,
            start: start
        ) {
            try await uploadDataWithProgress(
                request,
                body: body,
                onProgress: onProgress
            )
        }

        return try decodeResponse(
            data: data,
            response: response,
            method: method,
            path: path,
            start: start
        )
    }

    private func performTransport(
        method: String,
        path: String,
        start: Date,
        operation: () async throws -> (Data, URLResponse)
    ) async throws -> (Data, URLResponse) {
        do {
            return try await operation()
        } catch let apiError as APIError {
            throw apiError
        } catch let urlError as URLError {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            Log.error(
                .network,
                "✗ network \(method) \(path) (\(elapsed)ms): \(urlError.localizedDescription)"
            )
            throw APIError.network(urlError)
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            Log.error(
                .network,
                "✗ request \(method) \(path) (\(elapsed)ms): \(error.localizedDescription)"
            )
            throw error
        }
    }

    private func uploadDataWithProgress(
        _ request: URLRequest,
        body: Data,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        let state = UploadTaskState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, from: body) { data, response, error in
                    state.invalidateObservation()

                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let data, let response else {
                        continuation.resume(throwing: APIError.invalidResponse)
                        return
                    }

                    Task { @MainActor in onProgress(1) }
                    continuation.resume(returning: (data, response))
                }

                Task { @MainActor in onProgress(0) }
                let observation = task.progress.observe(\.fractionCompleted, options: [.new]) {
                    progress, _ in
                    let clamped = min(max(progress.fractionCompleted, 0), 1)
                    Task { @MainActor in onProgress(clamped) }
                }

                guard state.configure(task: task, observation: observation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                task.resume()
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func decodeResponse<Response: Decodable>(
        data: Data,
        response: URLResponse,
        method: String,
        path: String,
        start: Date
    ) throws -> Response {
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            Log.error(
                .network,
                "✗ invalid response \(method) \(path) (\(elapsed)ms): \(type(of: response))"
            )
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            Log.error(
                .network,
                "✗ \(http.statusCode) \(method) \(path) (\(elapsed)ms) body: \(Self.redactedBody(data))"
            )
            throw APIError.fromStatus(http.statusCode, body: data)
        }

        Log.info(.network, "← \(http.statusCode) \(method) \(path) (\(elapsed)ms)")

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        Log.debug(.network, "  response: \(Log.redactBody(String(data: data, encoding: .utf8) ?? ""))")

        do {
            return try Self.jsonDecoder.decode(Response.self, from: data)
        } catch {
            Log.error(
                .network,
                "✗ decode \(method) \(path) as \(Response.self): \(error.localizedDescription) body: \(Self.redactedBody(data))"
            )
            throw APIError.decoding(String(describing: error))
        }
    }

    private static func redactedBody(_ data: Data) -> String {
        if let body = String(data: data, encoding: .utf8) {
            return Log.redactBody(body)
        }

        return "<non-utf8 \(data.count) bytes>"
    }
}

private struct AnyEncodable: Encodable {
    let base: Encodable

    init(_ base: Encodable) {
        self.base = base
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
    }
}

private func decodeISO8601Date(_ rawValue: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = fractionalFormatter.date(from: rawValue) {
        return date
    }

    let plainFormatter = ISO8601DateFormatter()
    plainFormatter.formatOptions = [.withInternetDateTime]
    return plainFormatter.date(from: rawValue)
}
