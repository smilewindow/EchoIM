import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("LoginViewModel")
struct LoginViewModelTests {
    final class StubRepo: AuthRepository {
        var loginResult: Result<AuthResponse, Error> = .failure(APIError.invalidResponse)

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
    }

    @Test
    func invalidCredentialsSurfacesAsToast() async {
        let repo = StubRepo()
        repo.loginResult = .failure(APIError.unauthorized)
        var receivedToast: String?
        let viewModel = LoginViewModel(
            repo: repo,
            onSuccess: { _ in },
            onToast: { receivedToast = $0 }
        )
        viewModel.email = "a@b.c"
        viewModel.password = "wrong"
        await viewModel.submit()

        #expect(viewModel.state == .failed)
        #expect(receivedToast == "邮箱或密码错误")
    }

    @Test
    func networkErrorIsForwardedToErrorHandler() async {
        let repo = StubRepo()
        let expectedError = APIError.network(URLError(.notConnectedToInternet))
        repo.loginResult = .failure(expectedError)
        var receivedError: Error?
        var receivedToast: String?
        let viewModel = LoginViewModel(
            repo: repo,
            onSuccess: { _ in },
            onError: { receivedError = $0 },
            onToast: { receivedToast = $0 }
        )
        viewModel.email = "a@b.c"
        viewModel.password = "12345678"
        await viewModel.submit()

        #expect(viewModel.state == .failed)
        if let apiError = receivedError as? APIError {
            #expect(apiError == expectedError)
        } else {
            Issue.record("expected APIError.network")
        }
        #expect(receivedToast == nil)
    }

    @Test
    func blocksEmptyInput() async {
        let repo = StubRepo()
        var receivedToast: String?
        let viewModel = LoginViewModel(
            repo: repo,
            onSuccess: { _ in },
            onToast: { receivedToast = $0 }
        )
        viewModel.email = ""
        viewModel.password = ""
        await viewModel.submit()

        #expect(viewModel.state == .failed)
        #expect(receivedToast == "邮箱和密码不能为空")
    }

    @Test
    func successfulSubmitDoesNotCallHandlers() async {
        let repo = StubRepo()
        let user = AuthenticatedUser(
            id: 1,
            username: "u",
            email: "a@b.c",
            displayName: nil,
            avatarUrl: nil
        )
        var didCallOnError = false
        var didCallOnToast = false
        let viewModel = LoginViewModel(
            repo: repo,
            onSuccess: { _ in },
            onError: { _ in didCallOnError = true },
            onToast: { _ in didCallOnToast = true }
        )
        repo.loginResult = .success(AuthResponse(token: "t", user: user))
        viewModel.email = "a@b.c"
        viewModel.password = "12345678"
        await viewModel.submit()
        #expect(didCallOnError == false)
        #expect(didCallOnToast == false)
    }
}
