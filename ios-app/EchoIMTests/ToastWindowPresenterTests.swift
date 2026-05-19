import Testing
import UIKit
@testable import EchoIM

@MainActor
@Suite("ToastWindowPresenter")
struct ToastWindowPresenterTests {
    @Test
    func showCreatesSingleVisibleOverlayWindowAndHideRemovesIt() throws {
        let scene = try #require(Self.activeWindowScene())
        let presenter = ToastWindowPresenter()

        presenter.show(ToastMessage(message: "好友申请已存在"), in: scene)

        let firstWindow = try #require(presenter.overlayWindowForTesting)
        #expect(firstWindow.isHidden == false)
        #expect(firstWindow.windowScene === scene)
        #expect(firstWindow.windowLevel == UIWindow.Level.alert + 1)

        presenter.show(ToastMessage(message: "不能添加自己为好友"), in: scene)

        let secondWindow = try #require(presenter.overlayWindowForTesting)
        #expect(secondWindow === firstWindow)

        presenter.hide()

        #expect(presenter.overlayWindowForTesting == nil)
        #expect(firstWindow.isHidden)
    }

    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}
