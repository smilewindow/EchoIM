import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("ToastCenter")
struct ToastCenterTests {
    @Test
    func showErrorSuppressesCancelledRequests() {
        let center = ToastCenter()

        center.show(error: APIError.network(URLError(.cancelled)))

        #expect(center.current == nil)
    }

    @Test
    func showErrorDisplaysRealNetworkErrors() {
        let center = ToastCenter()

        center.show(error: APIError.network(URLError(.notConnectedToInternet)))

        #expect(center.current?.message == "网络不可用，请检查连接")
    }
}
