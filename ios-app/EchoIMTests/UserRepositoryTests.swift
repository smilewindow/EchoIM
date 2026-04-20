import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("UserRepository")
struct UserRepositoryTests {
    @Test
    func fetchMeHitsCorrectEndpointAndDecodes() async throws {
        var capturedPath: String?
        var capturedAuth: String?
        let body = """
        { "id": 42, "username": "me", "email": "me@x.com",
          "display_name": "Me", "avatar_url": "/uploads/avatars/42.jpg" }
        """.data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedPath = request.url?.path
            capturedAuth = request.value(forHTTPHeaderField: "Authorization")
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
        let client = APIClient(session: URLSession(configuration: configuration))
        let repo = UserRepositoryImpl(api: client)

        let user = try await repo.fetchMe(token: "jwt-1")

        #expect(capturedPath == "/api/users/me")
        #expect(capturedAuth == "Bearer jwt-1")
        #expect(user.id == 42)
        #expect(user.email == "me@x.com")
        #expect(user.displayName == "Me")
    }

    @Test
    func fetchMeThrowsUnauthorizedOn401() async throws {
        let (configuration, _) = MockURLProtocol.configure { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        let client = APIClient(session: URLSession(configuration: configuration))
        let repo = UserRepositoryImpl(api: client)

        do {
            _ = try await repo.fetchMe(token: "stale")
            Issue.record("expected .unauthorized")
        } catch let error as APIError {
            #expect(error == .unauthorized)
        }
    }

    @Test
    func searchBuildsQuerystring() async throws {
        var capturedURL: URL?
        let body = "[]".data(using: .utf8)!
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedURL = request.url
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
        let client = APIClient(session: URLSession(configuration: configuration))
        let repo = UserRepositoryImpl(api: client)

        _ = try await repo.searchUsers(query: "ali ce", token: "jwt")

        let components = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)!
        let query = components.queryItems?.first { $0.name == "q" }?.value
        #expect(query == "ali ce")
        #expect(capturedURL?.path == "/api/users/search")
    }
}
