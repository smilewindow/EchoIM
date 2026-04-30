import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("UploadRepository")
struct UploadRepositoryTests {
    @Test
    func uploadMessageImageReturnsMediaURL() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"media_url\":\"/uploads/messages/7-1745800000000.jpg\",\"media_width\":1600,\"media_height\":900}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        let uploaded = try await repo.uploadMessageImage(
            data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            token: "tok"
        )
        #expect(uploaded.mediaUrl == "/uploads/messages/7-1745800000000.jpg")
        #expect(uploaded.mediaWidth == 1600)
        #expect(uploaded.mediaHeight == 900)

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/upload/message-image")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.starts(with: "multipart/form-data; boundary="))

        let body = try #require(Self.bodyData(from: request))
        let bodyText = String(decoding: body, as: UTF8.self)
        #expect(bodyText.contains("name=\"file\""))
        #expect(bodyText.contains("filename=\"image.jpg\""))
        #expect(bodyText.contains("Content-Type: image/jpeg"))
    }

    @Test
    func uploadMessageImagePropagatesUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"error\":\"Unauthorized\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadMessageImage(data: Data([0xFF, 0xD8]), token: "tok")
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
    }

    @Test
    func uploadMessageImageMaps400ToHTTPStatus() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"error\":\"Invalid image file\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadMessageImage(data: Data([0x00]), token: "tok")
            Issue.record("expected APIError.http")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    @Test
    func boundaryIsUniquePerCall() async throws {
        nonisolated(unsafe) var boundaries: [String] = []
        let lock = NSLock()
        let (config, _) = MockURLProtocol.configure { request in
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            let boundary = String(contentType.split(separator: "=").last ?? "")
            lock.lock()
            boundaries.append(boundary)
            lock.unlock()
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"media_url\":\"/uploads/messages/1-1.jpg\",\"media_width\":10,\"media_height\":10}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        _ = try await repo.uploadMessageImage(data: Data([0xFF]), token: "t")
        _ = try await repo.uploadMessageImage(data: Data([0xFF]), token: "t")

        lock.lock()
        let recorded = boundaries
        lock.unlock()
        #expect(recorded.count == 2)
        #expect(recorded[0] != recorded[1], "每次调用必须用新的 boundary，避免请求间字节窜流")
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
