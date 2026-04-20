import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("LoginViewModel")
struct LoginViewModelTests {
    final class StubRepo: AuthRepository {
        var loginResult: Result<AuthResponse, Error> = .failure(AuthError.unknown(""))

        func login(email: String, password: String) async throws -> AuthResponse {
            try loginResult.get()
        }

        func register(_ request: RegisterRequest) async throws -> AuthResponse {
            fatalError()
        }

        func logout() async {}
    }

    @Test
    func submitsAndReportsSuccess() async {
        let repo = StubRepo()
        let user = AuthenticatedUser(
            id: 1,
            username: "u",
            email: "a@b.c",
            displayName: nil,
            avatarUrl: nil
        )
        repo.loginResult = .success(AuthResponse(token: "t", user: user))

        var received: AuthResponse?
        let viewModel = LoginViewModel(repo: repo) { received = $0 }
        viewModel.email = "a@b.c"
        viewModel.password = "12345678"
        await viewModel.submit()

        #expect(received?.user == user)
        #expect(viewModel.state == .success)
        #expect(viewModel.toast == nil)
    }

    @Test
    func invalidCredentialsSurfacesAsToast() async {
        let repo = StubRepo()
        repo.loginResult = .failure(AuthError.invalidCredentials)
        let viewModel = LoginViewModel(repo: repo) { _ in }
        viewModel.email = "a@b.c"
        viewModel.password = "wrong"
        await viewModel.submit()

        #expect(viewModel.toast == "邮箱或密码错误")
        if case .failed(let error) = viewModel.state {
            #expect(error == .invalidCredentials)
        } else {
            Issue.record("expected .failed(.invalidCredentials), got \(viewModel.state)")
        }
    }

    @Test
    func networkErrorSurfacesAsToast() async {
        let repo = StubRepo()
        repo.loginResult = .failure(AuthError.network)
        let viewModel = LoginViewModel(repo: repo) { _ in }
        viewModel.email = "a@b.c"
        viewModel.password = "12345678"
        await viewModel.submit()
        #expect(viewModel.toast == "网络错误，请检查连接")
    }

    @Test
    func blocksEmptyInput() async {
        let repo = StubRepo()
        let viewModel = LoginViewModel(repo: repo) { _ in }
        viewModel.email = ""
        viewModel.password = ""
        await viewModel.submit()

        #expect(viewModel.toast == "邮箱和密码不能为空")
        if case .failed(let error) = viewModel.state, case .fieldValidation = error {
            // ok
        } else {
            Issue.record("expected .fieldValidation, got \(viewModel.state)")
        }
    }

    @Test
    func submittingClearsStaleToast() async {
        let repo = StubRepo()
        let user = AuthenticatedUser(
            id: 1,
            username: "u",
            email: "a@b.c",
            displayName: nil,
            avatarUrl: nil
        )
        let viewModel = LoginViewModel(repo: repo) { _ in }
        viewModel.toast = "旧错误"
        repo.loginResult = .success(AuthResponse(token: "t", user: user))
        viewModel.email = "a@b.c"
        viewModel.password = "12345678"
        await viewModel.submit()
        #expect(viewModel.toast == nil)
    }
}
