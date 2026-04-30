import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("MessageRepository — sendImage")
struct MessageRepositorySendImageTests {
    @Test
    func sendImagePostsExpectedJSONBody() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            let body = """
            {
              "id": 101,
              "conversation_id": 5,
              "sender_id": 3,
              "body": null,
              "message_type": "image",
              "media_url": "/uploads/messages/3-1745800000000.jpg",
              "created_at": "2026-04-25T10:00:00.000Z",
              "client_temp_id": "tmp-img-1"
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = MessageRepositoryImpl(api: api)

        let result = try await repo.sendImage(
            recipientId: 9,
            mediaUrl: "/uploads/messages/3-1745800000000.jpg",
            mediaWidth: 1600,
            mediaHeight: 900,
            clientTempId: "tmp-img-1",
            token: "tok"
        )

        #expect(result.id == 101)
        #expect(result.messageType == "image")
        #expect(result.mediaUrl == "/uploads/messages/3-1745800000000.jpg")
        #expect(result.clientTempId == "tmp-img-1")

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/messages")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(Self.bodyData(from: request))
        let parsed = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(parsed?["recipient_id"] as? Int == 9)
        #expect(parsed?["media_url"] as? String == "/uploads/messages/3-1745800000000.jpg")
        #expect(parsed?["media_width"] as? Int == 1600)
        #expect(parsed?["media_height"] as? Int == 900)
        #expect(parsed?["message_type"] as? String == "image")
        #expect(parsed?["client_temp_id"] as? String == "tmp-img-1")
        #expect(parsed?["body"] == nil, "image 消息不应带 body 字段")
    }

    @Test
    func sendImagePropagates403WhenNotFriends() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"error\":\"Not friends\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = MessageRepositoryImpl(api: api)

        do {
            _ = try await repo.sendImage(
                recipientId: 9,
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                mediaWidth: 1600,
                mediaHeight: 900,
                clientTempId: "tmp",
                token: "tok"
            )
            Issue.record("expected APIError.http(403)")
        } catch APIError.http(let status, _) {
            #expect(status == 403)
        }
    }

    @Test
    func sendImagePropagates400WhenInvalidMediaURL() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                "{\"error\":\"Invalid media_url\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = MessageRepositoryImpl(api: api)

        do {
            _ = try await repo.sendImage(
                recipientId: 9,
                mediaUrl: "/wrongprefix/abc.jpg",
                mediaWidth: 1600,
                mediaHeight: 900,
                clientTempId: "tmp",
                token: "tok"
            )
            Issue.record("expected APIError.http(400)")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
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
