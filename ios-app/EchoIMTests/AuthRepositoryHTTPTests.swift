import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("AuthRepository HTTP integration (mocked URLSession)")
struct AuthRepositoryHTTPTests {
    private func makeClient(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> (APIClient, KeychainTokenStore) {
        let (configuration, _) = MockURLProtocol.configure(handler)
        let api = APIClient(session: URLSession(configuration: configuration))
        let tokenStore = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try? tokenStore.clear()
        return (api, tokenStore)
    }

    private func requestBodyData(from request: URLRequest?) throws -> Data {
        if let body = request?.httpBody {
            return body
        }

        guard let stream = request?.httpBodyStream else {
            throw CocoaError(.fileReadUnknown)
        }

        // URLProtocol 拦截到的请求有时只保留 httpBodyStream，不再暴露 httpBody。
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0 {
                throw stream.streamError ?? CocoaError(.fileReadUnknown)
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data
    }

    @Test
    func loginHitsCorrectEndpointAndStoresToken() async throws {
        var captured: URLRequest?
        let (api, tokenStore) = makeClient { request in
            captured = request
            let body = """
            {"token":"jwt-abc","user":{"id":7,"username":"alice","email":"a@b.c","display_name":null,"avatar_url":null}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        let repository = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        let response = try await repository.login(email: "a@b.c", password: "password123")

        #expect(captured?.httpMethod == "POST")
        #expect(captured?.url?.path.hasSuffix("/api/auth/login") == true)

        let bodyData = try requestBodyData(from: captured)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(json?["email"] as? String == "a@b.c")
        #expect(json?["password"] as? String == "password123")
        #expect(json?.count == 2)

        let stored = try tokenStore.load()
        #expect(stored?.token == "jwt-abc")
        #expect(stored?.userId == 7)
        #expect(response.user.username == "alice")

        try tokenStore.clear()
    }

    @Test
    func registerSendsCamelCaseInviteCodeAndStoresToken() async throws {
        var captured: URLRequest?
        let (api, tokenStore) = makeClient { request in
            captured = request
            let body = """
            {"token":"jwt-xyz","user":{"id":11,"username":"bob","email":"b@c.d","display_name":"Bob","avatar_url":null}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        let repository = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        _ = try await repository.register(RegisterRequest(
            username: "bob",
            email: "b@c.d",
            password: "password123",
            inviteCode: "INVITE1"
        ))

        #expect(captured?.url?.path.hasSuffix("/api/auth/register") == true)

        let bodyData = try requestBodyData(from: captured)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        // 关键断言：注册接口必须发送 camelCase 的 inviteCode，不能误发 invite_code。
        #expect(json?["inviteCode"] as? String == "INVITE1")
        #expect(json?["invite_code"] == nil)
        #expect(json?["username"] as? String == "bob")
        #expect(json?["email"] as? String == "b@c.d")
        #expect(json?["password"] as? String == "password123")

        let stored = try tokenStore.load()
        #expect(stored?.token == "jwt-xyz")
        #expect(stored?.userId == 11)

        try tokenStore.clear()
    }

    @Test
    func registerReturns403InvalidInviteCode() async throws {
        let (api, tokenStore) = makeClient { request in
            let body = try! JSONSerialization.data(withJSONObject: ["error": "Invalid invite code"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        let repository = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        do {
            _ = try await repository.register(RegisterRequest(
                username: "x",
                email: "x@y.z",
                password: "12345678",
                inviteCode: "BAD"
            ))
            Issue.record("expected throw")
        } catch let error as AuthError {
            #expect(error == .invalidInviteCode)
        }

        #expect(try tokenStore.load() == nil)
    }

    @Test
    func loginReturns401InvalidCredentials() async throws {
        let (api, tokenStore) = makeClient { request in
            let body = try! JSONSerialization.data(withJSONObject: ["error": "Invalid email or password"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, body)
        }
        let repository = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        do {
            _ = try await repository.login(email: "a@b.c", password: "wrong")
            Issue.record("expected throw")
        } catch let error as AuthError {
            #expect(error == .invalidCredentials)
        }

        #expect(try tokenStore.load() == nil)
    }
}
