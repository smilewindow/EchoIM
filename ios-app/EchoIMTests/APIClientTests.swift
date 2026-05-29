import Testing
import Foundation
@testable import EchoIM

@Suite("APIClient JSON decoding")
struct APIClientTests {
    @Test
    @MainActor
    func decodesMessageWithFractionalSeconds() throws {
        let json = """
        {
          "id": 42,
          "conversation_id": 7,
          "sender_id": 3,
          "body": "hi",
          "message_type": "text",
          "media_url": null,
          "created_at": "2026-04-19T08:30:12.345Z",
          "client_temp_id": null
        }
        """.data(using: .utf8)!

        let decoder = APIClient.jsonDecoder
        let message = try decoder.decode(Message.self, from: json)
        #expect(message.id == 42)
        #expect(message.conversationId == 7)
        #expect(message.senderId == 3)
        #expect(message.body == "hi")
        #expect(message.messageType == "text")
        #expect(message.mediaUrl == nil)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(message.createdAt == formatter.date(from: "2026-04-19T08:30:12.345Z"))
    }

    @Test
    @MainActor
    func throwsUnauthorizedOn401() async throws {
        let url = URL(string: "http://test.local/fail")!
        let (configuration, _) = MockURLProtocol.configure { _ in
            (
                HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let client = APIClient(session: URLSession(configuration: configuration))

        do {
            let _: EmptyResponse = try await client.request("x")
            Issue.record("expected .unauthorized")
        } catch let error as APIError {
            #expect(error == .unauthorized)
        }
    }

    @Test
    @MainActor
    func progressUploadAcceptsBodyWithoutRequestHTTPBody() async throws {
        let url = URL(string: "http://test.local/upload")!
        var capturedRequest: URLRequest?
        let (configuration, _) = MockURLProtocol.configure { request in
            capturedRequest = request
            return (
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{}".data(using: .utf8)!
            )
        }
        let client = APIClient(session: URLSession(configuration: configuration))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = Data([0x01, 0x02, 0x03])
        var progressValues: [Double] = []

        let _: EmptyResponse = try await client.executeUploadWithProgress(
            request,
            method: "POST",
            path: "/upload",
            body: body,
            onProgress: { progress in progressValues.append(progress) }
        )
        await Task.yield()

        let sentRequest = try #require(capturedRequest)
        #expect(sentRequest.httpBody == nil)
        #expect(progressValues.contains(0))
        #expect(progressValues.contains(1))
    }

    @Test
    @MainActor
    func requestMapsURLErrorToNetworkError() async throws {
        let configuration = FailingURLProtocol.configuration(error: URLError(.timedOut))
        let client = APIClient(session: URLSession(configuration: configuration))

        do {
            let _: EmptyResponse = try await client.request("/transport-fail")
            Issue.record("expected APIError.network")
        } catch APIError.network(let urlError) {
            #expect(urlError.code == .timedOut)
        }
    }

    @Test
    @MainActor
    func progressUploadMapsURLErrorToNetworkError() async throws {
        let configuration = FailingURLProtocol.configuration(error: URLError(.timedOut))
        let client = APIClient(session: URLSession(configuration: configuration))
        let url = URL(string: "http://test.local/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let _: EmptyResponse = try await client.executeUploadWithProgress(
                request,
                method: "POST",
                path: "/upload",
                body: Data([0x01]),
                onProgress: { _ in }
            )
            Issue.record("expected APIError.network")
        } catch APIError.network(let urlError) {
            #expect(urlError.code == .timedOut)
        }
    }
}

private final class FailingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var error: Error = URLError(.unknown)

    static func configuration(error: Error) -> URLSessionConfiguration {
        lock.lock()
        self.error = error
        lock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let error = Self.error
        Self.lock.unlock()

        client?.urlProtocol(self, didFailWithError: error)
    }

    override func stopLoading() {}
}
