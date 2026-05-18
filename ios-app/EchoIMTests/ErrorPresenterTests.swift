import Foundation
import Testing
@testable import EchoIM

@Suite("ErrorPresenter")
struct ErrorPresenterTests {
    @Test
    func mapsKnownServerCodeToLocalizedMessage() {
        let body = """
        {
          "error": {
            "code": "friend_request_already_exists",
            "message": "Friend request already exists"
          }
        }
        """.data(using: .utf8)!
        let error = APIError.http(status: 409, body: body)

        #expect(ErrorPresenter.message(for: error) == "好友申请已存在")
    }

    @Test
    func fallsBackToServerMessageForUnknownServerCode() {
        let body = """
        {
          "error": {
            "code": "new_server_code",
            "message": "New server fallback"
          }
        }
        """.data(using: .utf8)!
        let error = APIError.http(status: 499, body: body)

        #expect(ErrorPresenter.message(for: error) == "New server fallback")
    }

    @Test
    func mapsNetworkErrorLocally() {
        let error = APIError.network(URLError(.notConnectedToInternet))

        #expect(ErrorPresenter.message(for: error) == "网络不可用，请检查连接")
    }

    @Test
    func suppressesCancelledNetworkErrorForDisplay() {
        let error = APIError.network(URLError(.cancelled))

        #expect(ErrorPresenter.displayMessage(for: error) == nil)
    }

    @Test
    func keepsRealNetworkErrorDisplayMessage() {
        let error = APIError.network(URLError(.notConnectedToInternet))

        #expect(ErrorPresenter.displayMessage(for: error) == "网络不可用，请检查连接")
    }
}
