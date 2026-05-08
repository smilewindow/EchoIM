import Foundation

extension APIClient {
    /// multipart/form-data 上传。与 JSON request 共享 status code 与 decoder 处理。
    /// 使用 `data(for:)` 保留 `httpBody`，方便测试断言 multipart 字节形状。
    func upload<Response: Decodable>(
        _ path: String,
        boundary: String,
        body: Data,
        token: String
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Endpoints.baseURL)?.absoluteURL else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        Log.info(.network, "→ UPLOAD POST \(path) (\(body.count / 1024)KB)")

        let data: Data
        let response: URLResponse
        let start = Date()
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            Log.error(.network, "✗ network \(urlError.localizedDescription)")
            throw APIError.network(urlError)
        }

        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            Log.error(.network, "✗ \(http.statusCode) POST \(path) (\(elapsed)ms)")
            throw APIError.fromStatus(http.statusCode, body: data)
        }

        Log.info(.network, "← \(http.statusCode) POST \(path) (\(elapsed)ms)")
        #if DEBUG
        Log.debug(.network, "  response: \(Log.redactBody(String(data: data, encoding: .utf8) ?? ""))")
        #endif

        do {
            return try Self.jsonDecoder.decode(Response.self, from: data)
        } catch {
            Log.error(.network, "✗ decode \(Response.self): \(error.localizedDescription)")
            throw APIError.decoding(String(describing: error))
        }
    }
}
