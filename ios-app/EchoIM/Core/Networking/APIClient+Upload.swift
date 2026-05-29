import Foundation

extension APIClient {
    /// multipart/form-data 上传。与 JSON request 共享 status code 与 decoder 处理。
    /// 无进度路径保留 `httpBody` 方便测试断言 multipart 字节形状；
    /// 进度路径由 `uploadTask(from:)` 持有 body，避免 request 和 task 双份保留大图。
    func upload<Response: Decodable>(
        _ path: String,
        boundary: String,
        body: Data,
        token: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Endpoints.baseURL)?.absoluteURL else {
            Log.error(.network, "✗ invalid URL POST \(path)")
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

        Log.info(.network, "→ UPLOAD POST \(path) (\(body.count / 1024)KB)")

        guard let onProgress else {
            req.httpBody = body
            return try await execute(req, method: "POST", path: path)
        }

        return try await executeUploadWithProgress(
            req,
            method: "POST",
            path: path,
            body: body,
            onProgress: onProgress
        )
    }
}
