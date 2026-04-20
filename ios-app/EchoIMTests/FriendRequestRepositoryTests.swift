import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("FriendRequestRepository")
struct FriendRequestRepositoryTests {
    @Test
    func listIncomingHitsEndpoint() async throws {
        var capturedPath: String?
        let body = "[]".data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedPath = request.url?.path
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        let repo = FriendRequestRepositoryImpl(
            api: APIClient(session: URLSession(configuration: configuration))
        )

        _ = try await repo.listIncoming(token: "jwt")

        #expect(capturedPath == "/api/friend-requests")
    }

    @Test
    func listSentAndHistoryHitCorrectEndpoints() async throws {
        var paths: [String] = []
        let body = "[]".data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            paths.append(request.url?.path ?? "")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        let repo = FriendRequestRepositoryImpl(
            api: APIClient(session: URLSession(configuration: configuration))
        )

        _ = try await repo.listSent(token: "jwt")
        _ = try await repo.listHistory(token: "jwt")

        #expect(paths == ["/api/friend-requests/sent", "/api/friend-requests/history"])
    }

    @Test
    func sendEncodesSnakeCaseRecipientId() async throws {
        var capturedBody: Data?
        var capturedMethod: String?
        let body = """
        { "id": 20, "sender_id": 1, "recipient_id": 2, "status": "pending",
          "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:30:12.345Z" }
        """.data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedMethod = request.httpMethod
            if let stream = request.httpBodyStream {
                capturedBody = Data(reading: stream)
            } else {
                capturedBody = request.httpBody
            }
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
        let repo = FriendRequestRepositoryImpl(
            api: APIClient(session: URLSession(configuration: configuration))
        )

        let result = try await repo.send(recipientId: 2, token: "jwt")

        #expect(capturedMethod == "POST")
        let dictionary = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        #expect(dictionary?["recipient_id"] as? Int == 2)
        #expect(dictionary?["recipientId"] == nil)
        #expect(result.id == 20)
    }

    @Test
    func respondSendsStatusOnPut() async throws {
        var capturedMethod: String?
        var capturedPath: String?
        var capturedBody: Data?
        let body = """
        { "id": 20, "sender_id": 1, "recipient_id": 2, "status": "accepted",
          "created_at": "2026-04-19T08:30:12.345Z", "updated_at": "2026-04-19T08:31:00.000Z" }
        """.data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedMethod = request.httpMethod
            capturedPath = request.url?.path
            if let stream = request.httpBodyStream {
                capturedBody = Data(reading: stream)
            } else {
                capturedBody = request.httpBody
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                body
            )
        }
        let repo = FriendRequestRepositoryImpl(
            api: APIClient(session: URLSession(configuration: configuration))
        )

        let result = try await repo.respond(id: 20, accept: true, token: "jwt")

        #expect(capturedMethod == "PUT")
        #expect(capturedPath == "/api/friend-requests/20")
        let dictionary = try JSONSerialization.jsonObject(with: capturedBody ?? Data()) as? [String: Any]
        #expect(dictionary?["status"] as? String == "accepted")
        #expect(result.status == .accepted)
    }
}

private extension Data {
    init(reading input: InputStream) {
        self.init()
        input.open()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer {
            buffer.deallocate()
            input.close()
        }

        while input.hasBytesAvailable {
            let count = input.read(buffer, maxLength: size)
            if count <= 0 {
                break
            }
            self.append(buffer, count: count)
        }
    }
}
