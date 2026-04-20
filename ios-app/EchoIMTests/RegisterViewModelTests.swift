import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("RegisterViewModel")
struct RegisterViewModelTests {
    final class StubRepo: AuthRepository {
        var registerResult: Result<AuthResponse, Error> = .failure(AuthError.unknown(""))

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
        repo.registerResult = .failure(AuthError.emailTaken)
        let viewModel = viewModel(repo)
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.emailError == "邮箱已被注册")
        #expect(viewModel.usernameError == nil)
        #expect(viewModel.toast == nil)
    }

    @Test
    func mapsUsernameTakenToUsernameError() async {
        let repo = StubRepo()
        repo.registerResult = .failure(AuthError.usernameTaken)
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
    func mapsInvalidInviteCodeToFieldAndToast() async {
        let repo = StubRepo()
        repo.registerResult = .failure(AuthError.invalidInviteCode)
        let viewModel = viewModel(repo)
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "WRONG"
        await viewModel.submit()
        #expect(viewModel.inviteCodeError == "邀请码无效")
        #expect(viewModel.toast == "邀请码无效")
    }

    @Test
    func mapsFieldValidationEmailToEmailError() async {
        let repo = StubRepo()
        repo.registerResult = .failure(
            AuthError.fieldValidation(field: .email, message: "Invalid email address")
        )
        let viewModel = viewModel(repo)
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.emailError == "Invalid email address")
        #expect(viewModel.toast == nil)
    }

    @Test
    func mapsFieldValidationUnknownToToast() async {
        let repo = StubRepo()
        repo.registerResult = .failure(
            AuthError.fieldValidation(field: nil, message: "server said something weird")
        )
        let viewModel = viewModel(repo)
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.toast == "server said something weird")
        #expect(viewModel.emailError == nil)
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
        viewModel.toast = "stale"
        viewModel.username = "alice"
        viewModel.email = "a@b.co"
        viewModel.password = "12345678"
        viewModel.inviteCode = "X"
        await viewModel.submit()
        #expect(viewModel.emailError == nil)
        #expect(viewModel.usernameError == nil)
        #expect(viewModel.toast == nil)
    }
}
