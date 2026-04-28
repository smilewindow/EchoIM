import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("UploadRepository.uploadAvatar")
struct UploadRepositoryAvatarTests {
    @Test
    func uploadAvatarReturnsAvatarURL() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{\"avatar_url\":\"/uploads/avatars/7-1745900000000.jpg\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        let url = try await repo.uploadAvatar(
            data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            token: "tok"
        )
        #expect(url == "/uploads/avatars/7-1745900000000.jpg")

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/upload/avatar")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.starts(with: "multipart/form-data; boundary="))

        let body = try #require(Self.bodyData(from: request))
        let bodyText = String(decoding: body, as: UTF8.self)
        #expect(bodyText.contains("name=\"file\""))
        #expect(bodyText.contains("filename=\"avatar.jpg\""))
        #expect(bodyText.contains("Content-Type: image/jpeg"))
    }

    @Test
    func uploadAvatarPropagatesUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadAvatar(data: Data([0xFF]), token: "stale")
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
    }

    @Test
    func uploadAvatarPropagates400ForInvalidImage() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Invalid image file\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadAvatar(data: Data([0x00]), token: "t")
            Issue.record("expected APIError.http(400)")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
