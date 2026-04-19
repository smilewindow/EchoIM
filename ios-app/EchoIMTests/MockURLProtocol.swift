import Foundation

final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static let sessionHeader = "X-Mock-Session-ID"

    // 测试 handler 往往会捕获可变局部变量，这里用 lock 保护字典读写，避免并行测试串台。
    nonisolated(unsafe) private static var handlers:
        [String: (URLRequest) -> (HTTPURLResponse, Data)] = [:]

    static func configure(
        _ handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> (URLSessionConfiguration, Void) {
        let sessionID = UUID().uuidString

        lock.lock()
        handlers[sessionID] = handler
        lock.unlock()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpAdditionalHeaders = [sessionHeader: sessionID]
        return (configuration, ())
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: sessionHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let sessionID = request.value(forHTTPHeaderField: Self.sessionHeader) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Self.lock.lock()
        let handler = Self.handlers[sessionID]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
