import Foundation

protocol UploadRepository {
    /// 上传已压缩的消息图片 JPEG，返回服务端分配的 media_url。
    /// 调用方必须原样传给发消息接口，客户端不要自行拼路径。
    func uploadMessageImage(data: Data, token: String) async throws -> String
}

private struct UploadMessageImageResponse: Decodable {
    let mediaUrl: String
}

@MainActor
final class UploadRepositoryImpl: UploadRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.makeMultipartBody(
            fieldName: "file",
            filename: "image.jpg",
            contentType: "image/jpeg",
            payload: data,
            boundary: boundary
        )

        let response: UploadMessageImageResponse = try await api.upload(
            Endpoints.Upload.messageImage,
            boundary: boundary,
            body: body,
            token: token
        )
        return response.mediaUrl
    }

    /// CRLF 和字段名都要和服务端 multipart 解析契约对齐。
    private static func makeMultipartBody(
        fieldName: String,
        filename: String,
        contentType: String,
        payload: Data,
        boundary: String
    ) -> Data {
        let crlf = "\r\n"
        var body = Data()
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\(crlf)"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(payload)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
}
