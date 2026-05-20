import SwiftUI
import Testing
import UIKit
@testable import EchoIM

@MainActor
@Suite("Auth toast presentation")
struct AuthToastPresentationTests {
    @Test
    func loginToastIsForwardedToGlobalToastAndCleared() throws {
        let viewModel = LoginViewModel(repo: StubAuthRepository()) { _ in }
        var shownMessages: [String] = []

        let window = try Self.render(
            LoginView(vm: viewModel) {}
                .environment(\.showToast) { message in
                    shownMessages.append(message)
                }
        )
        defer { window.isHidden = true }

        viewModel.toast = "邮箱或密码错误"
        Self.pumpRunLoop()

        #expect(shownMessages == ["邮箱或密码错误"])
        #expect(viewModel.toast == nil)
    }

    @Test
    func registerToastIsForwardedToGlobalToastAndFieldErrorStays() throws {
        let viewModel = RegisterViewModel(repo: StubAuthRepository()) { _ in }
        viewModel.inviteCodeError = "邀请码无效"
        var shownMessages: [String] = []

        let window = try Self.render(
            RegisterView(vm: viewModel) {}
                .environment(\.showToast) { message in
                    shownMessages.append(message)
                }
        )
        defer { window.isHidden = true }

        viewModel.toast = "邀请码无效"
        Self.pumpRunLoop()

        #expect(shownMessages == ["邀请码无效"])
        #expect(viewModel.toast == nil)
        #expect(viewModel.inviteCodeError == "邀请码无效")
    }

    private static func render<Content: View>(_ view: Content) throws -> UIWindow {
        let scene = try #require(activeWindowScene())
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        pumpRunLoop()
        return window
    }

    private static func pumpRunLoop() {
        // SwiftUI 的 Observation 更新会排到主循环；测试里主动推进一次，避免读到旧 UI 状态。
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

private final class StubAuthRepository: AuthRepository {
    func login(email: String, password: String) async throws -> AuthResponse {
        throw AuthError.unknown("unused")
    }

    func register(_ request: RegisterRequest) async throws -> AuthResponse {
        throw AuthError.unknown("unused")
    }

    func logout() async {}
}
