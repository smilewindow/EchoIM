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

    @Test
    func decodesStructuredServerErrorFromHTTPBody() throws {
        let body = """
        {
          "error": {
            "code": "friend_request_already_exists",
            "message": "Friend request already exists"
          }
        }
        """.data(using: .utf8)!
        let error = APIError.http(status: 409, body: body)

        #expect(error.serverError?.code == "friend_request_already_exists")
        #expect(error.serverError?.message == "Friend request already exists")
    }

    @Test
    func fallsBackWhenHTTPBodyIsMalformed() {
        let error = APIError.http(status: 500, body: Data("oops".utf8))

        #expect(error.serverError == nil)
    }
}
