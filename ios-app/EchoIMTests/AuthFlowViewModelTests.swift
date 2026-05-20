import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("AuthFlowViewModel")
struct AuthFlowViewModelTests {
    @Test
    func unrelatedToastDoesNotClearAuthInput() {
        let container = AppContainer(
            tokenStore: KeychainTokenStore(service: "AuthFlowViewModelTests-\(UUID().uuidString)"),
            resetKeychainOnLaunch: true
        )
        let viewModel = AuthFlowViewModel(
            makeRepository: { container.makeAuthRepository() },
            onSuccess: { _ in }
        )
        viewModel.login.email = "smoke@test.local"
        viewModel.login.password = "password123"
        viewModel.register.inviteCode = "INVITE"
        viewModel.register.username = "alice"
        viewModel.register.email = "new@test.local"
        viewModel.register.password = "password456"

        container.showToast("邮箱或密码错误")

        #expect(viewModel.login.email == "smoke@test.local")
        #expect(viewModel.login.password == "password123")
        #expect(viewModel.register.inviteCode == "INVITE")
        #expect(viewModel.register.username == "alice")
        #expect(viewModel.register.email == "new@test.local")
        #expect(viewModel.register.password == "password456")
    }

    @Test
    func resetDropsPreviousLoginAndRegisterState() {
        let container = AppContainer(
            tokenStore: KeychainTokenStore(service: "AuthFlowViewModelTests-\(UUID().uuidString)"),
            resetKeychainOnLaunch: true
        )
        let viewModel = AuthFlowViewModel(
            makeRepository: { container.makeAuthRepository() },
            onSuccess: { _ in }
        )
        let oldLogin = viewModel.login
        let oldRegister = viewModel.register
        viewModel.login.email = "smoke@test.local"
        viewModel.login.password = "password123"
        viewModel.register.email = "new@test.local"
        viewModel.register.password = "password123"
        viewModel.register.inviteCode = "INVITE"

        viewModel.reset()

        #expect(viewModel.login !== oldLogin)
        #expect(viewModel.register !== oldRegister)
        #expect(viewModel.login.email.isEmpty)
        #expect(viewModel.login.password.isEmpty)
        #expect(viewModel.register.email.isEmpty)
        #expect(viewModel.register.password.isEmpty)
        #expect(viewModel.register.inviteCode.isEmpty)
    }
}
