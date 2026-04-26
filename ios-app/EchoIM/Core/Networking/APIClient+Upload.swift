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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.fromStatus(http.statusCode, body: data)
        }

        do {
            return try Self.jsonDecoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
