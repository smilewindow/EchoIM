import Testing
import Foundation
@testable import EchoIM

@Suite("APIError")
struct APIErrorTests {
    @Test
    func unauthorizedFrom401() {
        let err = APIError.fromStatus(401, body: Data())

        if case .unauthorized = err { return }
        Issue.record("expected .unauthorized, got \(err)")
    }

    @Test
    func httpCarriesStatusAndBody() {
        let body = Data("oops".utf8)
        let err = APIError.fromStatus(500, body: body)

        if case .http(let status, let responseBody) = err {
            #expect(status == 500)
            #expect(responseBody == body)
        } else {
            Issue.record("expected .http, got \(err)")
        }
    }
}
