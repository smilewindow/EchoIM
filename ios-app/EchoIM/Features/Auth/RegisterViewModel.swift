import Foundation
import Observation

@MainActor
@Observable
final class RegisterViewModel {
    enum State: Equatable {
        case idle
        case submitting
        case failed
        case success
    }

    var inviteCode = ""
    var username = ""
    var email = ""
    var password = ""

    var inviteCodeError: String?
    var usernameError: String?
    var emailError: String?
    var passwordError: String?
    var state: State = .idle

    private let repo: AuthRepository
    private let onSuccess: (AuthResponse) -> Void
    private var onError: @MainActor (Error) -> Void

    init(
        repo: AuthRepository,
        onSuccess: @escaping (AuthResponse) -> Void,
        onError: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.repo = repo
        self.onSuccess = onSuccess
        self.onError = onError
    }

    func setOnErrorHandler(_ handler: @escaping @MainActor (Error) -> Void) {
        onError = handler
    }

    func submit() async {
        clearFieldErrors()

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedInviteCode = inviteCode.trimmingCharacters(in: .whitespaces)

        if trimmedInviteCode.isEmpty {
            inviteCodeError = String(localized: "邀请码不能为空")
        }
        if trimmedUsername.count < 3 {
            usernameError = String(localized: "用户名至少 3 位")
        }
        if !Self.isValidEmail(trimmedEmail) {
            emailError = String(localized: "邮箱格式不正确")
        }
        if password.count < 8 {
            passwordError = String(localized: "密码至少 8 位")
        }

        guard inviteCodeError == nil,
              usernameError == nil,
              emailError == nil,
              passwordError == nil else {
            state = .failed
            return
        }

        state = .submitting

        do {
            let response = try await repo.register(RegisterRequest(
                username: trimmedUsername,
                email: trimmedEmail,
                password: password,
                inviteCode: trimmedInviteCode
            ))
            state = .success
            onSuccess(response)
        } catch {
            handleRegisterError(error)
            state = .failed
        }
    }

    private func clearFieldErrors() {
        inviteCodeError = nil
        usernameError = nil
        emailError = nil
        passwordError = nil
    }

    private func handleRegisterError(_ error: Error) {
        guard let apiError = error as? APIError,
              let knownCode = apiError.serverError?.knownCode else {
            onError(error)
            return
        }

        let errorMessage = ErrorPresenter.message(for: apiError)

        switch knownCode {
        case .invalidInviteCode:
            // 字段错误直接落到输入框下方，避免和全局 toast 重复。
            inviteCodeError = String(localized: "邀请码无效")
        case .emailAlreadyInUse:
            emailError = String(localized: "邮箱已被注册")
        case .usernameAlreadyTaken:
            usernameError = String(localized: "用户名已被占用")
        case .invalidEmail:
            emailError = errorMessage
        case .usernameTooShort:
            usernameError = errorMessage
        default:
            onError(error)
        }
    }

    nonisolated private static let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#

    nonisolated static func isValidEmail(_ string: String) -> Bool {
        string.range(of: emailRegex, options: .regularExpression) != nil
    }
}
