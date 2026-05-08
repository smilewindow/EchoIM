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

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        req.httpBody = body

        Log.info(.network, "→ UPLOAD POST \(path) (\(body.count / 1024)KB)")

        return try await execute(req, method: "POST", path: path)
    }
}
