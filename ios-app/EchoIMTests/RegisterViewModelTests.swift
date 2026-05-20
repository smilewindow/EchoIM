import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("RegisterViewModel")
struct RegisterViewModelTests {
    final class StubRepo: AuthRepository {
        var registerResult: Result<AuthResponse, Error> = .failure(APIError.invalidResponse)

        func login(email: String, password: String) async throws -> AuthResponse {
            fatalError()
        }

        func register(_ request: RegisterRequest) async throws -> AuthResponse {
            try registerResult.get()
        }

        func logout() async {}
    }

    func viewModel(_ repo: AuthRepository) -> RegisterViewModel {
        RegisterViewModel(repo: repo) { _ in }
    }

    func apiError(_ code: KnownServerErrorCode, message: String) -> APIError {
        let body = try! JSONSerialization.data(withJSONObject: [
            "error": [
                "code": code.rawValue,
                "message": message,
            ],
        ])
        return APIError.http(status: 400, body: body)
    }

    @Test
    func localValidationBlocksShortUsername() async {
        let viewModel = viewModel(StubRepo())
        viewModel.username = "ab"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.usernameError != nil)
        if case .failed = viewModel.state {
            // ok
        } else {
            Issue.record("expected .failed")
        }
    }

    @Test
    func localValidationBlocksBadEmail() async {
        let viewModel = viewModel(StubRepo())
        viewModel.username = "alice"
        viewModel.email = "not-email"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.emailError != nil)
    }

    @Test
    func localValidationBlocksShortPassword() async {
        let viewModel = viewModel(StubRepo())
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "short"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.passwordError != nil)
    }

    @Test
    func localValidationBlocksEmptyInvite() async {
        let viewModel = viewModel(StubRepo())
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = ""
        await viewModel.submit()
        #expect(viewModel.inviteCodeError != nil)
    }

    @Test
    func mapsEmailTakenToEmailErrorOnly() async {
        let repo = StubRepo()
        repo.registerResult = .failure(apiError(.emailAlreadyInUse, message: "Email already in use"))
        var didCallOnError = false
        let viewModel = RegisterViewModel(
            repo: repo,
            onSuccess: { _ in },
            onError: { _ in didCallOnError = true }
        )
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.emailError == "邮箱已被注册")
        #expect(viewModel.usernameError == nil)
        #expect(didCallOnError == false)
    }

    @Test
    func mapsUsernameTakenToUsernameError() async {
        let repo = StubRepo()
        repo.registerResult = .failure(apiError(.usernameAlreadyTaken, message: "Username already taken"))
        let viewModel = viewModel(repo)
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.usernameError == "用户名已被占用")
        #expect(viewModel.emailError == nil)
    }

    @Test
    func mapsUsernameTooShortToUsernameError() async {
        let repo = StubRepo()
        repo.registerResult = .failure(
            apiError(.usernameTooShort, message: "Username must be at least 3 characters")
        )
        let viewModel = viewModel(repo)
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.usernameError == "用户名至少需要 3 个字符")
    }

    @Test
    func mapsInvalidInviteCodeToFieldError() async {
        let repo = StubRepo()
        repo.registerResult = .failure(apiError(.invalidInviteCode, message: "Invalid invite code"))
        let viewModel = RegisterViewModel(
            repo: repo,
            onSuccess: { _ in }
        )
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "WRONG"
        await viewModel.submit()
        #expect(viewModel.inviteCodeError == "邀请码无效")
    }

    @Test
    func mapsInvalidEmailToEmailError() async {
        let repo = StubRepo()
        repo.registerResult = .failure(apiError(.invalidEmail, message: "Invalid email address"))
        let viewModel = viewModel(repo)
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.emailError == "邮箱格式不正确")
    }

    @Test
    func invalidRequestIsForwardedToErrorHandler() async {
        let repo = StubRepo()
        let expectedError = apiError(
            .invalidRequest,
            message: "body must have required property 'username'"
        )
        repo.registerResult = .failure(expectedError)
        var receivedError: Error?
        let viewModel = RegisterViewModel(
            repo: repo,
            onSuccess: { _ in },
            onError: { receivedError = $0 }
        )
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()

        #expect(viewModel.inviteCodeError == nil)
        #expect(viewModel.emailError == nil)
        #expect(viewModel.usernameError == nil)
        if let apiError = receivedError as? APIError {
            #expect(apiError == expectedError)
        } else {
            Issue.record("expected invalid_request APIError")
        }
    }

    @Test
    func submitClearsStaleErrors() async {
        let repo = StubRepo()
        let user = AuthenticatedUser(
            id: 1,
            username: "alice",
            email: "a@b.co",
            displayName: nil,
            avatarUrl: nil
        )
        repo.registerResult = .success(AuthResponse(token: "t", user: user))
        let viewModel = viewModel(repo)
        viewModel.emailError = "stale"
        viewModel.usernameError = "stale"
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.emailError == nil)
        #expect(viewModel.usernameError == nil)
    }
}
