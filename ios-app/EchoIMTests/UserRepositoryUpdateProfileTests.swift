import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("UserRepository.updateProfile")
struct UserRepositoryUpdateProfileTests {
    @Test
    func updateProfileSendsDisplayNameAndDecodesUser() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            let body = """
            { "id": 7, "username": "alice", "email": "a@x.com",
              "display_name": "Alice 2", "avatar_url": "/uploads/avatars/7-1.jpg" }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: api)

        let user = try await repo.updateProfile(displayName: "Alice 2", token: "tok-1")

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/api/users/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")

        // body 必须是 { "display_name": "Alice 2" }，不能含 avatar_url 键（不变式 2）。
        let bodyData = try #require(request.httpBody ?? Self.bodyData(from: request))
        let json = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["display_name"] as? String == "Alice 2")
        #expect(json["avatar_url"] == nil)
        #expect(json.count == 1)

        #expect(user.id == 7)
        #expect(user.username == "alice")
        #expect(user.displayName == "Alice 2")
        #expect(user.avatarUrl == "/uploads/avatars/7-1.jpg")
    }

    @Test
    func updateProfilePropagatesUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"User no longer exists\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: api)

        do {
            _ = try await repo.updateProfile(displayName: "Whatever", token: "stale")
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // 期望路径
        }
    }

    @Test
    func updateProfilePropagates400() async throws {
        let (config, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"display_name must NOT have more than 100 characters\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UserRepositoryImpl(api: api)

        do {
            _ = try await repo.updateProfile(displayName: String(repeating: "x", count: 101), token: "t")
            Issue.record("expected APIError.http(400)")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    private static func bodyData(from request: URLRequest) -> Data? {
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
