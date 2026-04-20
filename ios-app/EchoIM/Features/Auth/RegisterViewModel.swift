import Foundation
import Observation

@MainActor
@Observable
final class RegisterViewModel {
    enum State: Equatable {
        case idle
        case submitting
        case failed(AuthError)
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
    var toast: String?
    var state: State = .idle

    private let repo: AuthRepository
    private let onSuccess: (AuthResponse) -> Void

    init(repo: AuthRepository, onSuccess: @escaping (AuthResponse) -> Void) {
        self.repo = repo
        self.onSuccess = onSuccess
    }

    func submit() async {
        clearFieldErrors()

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedInviteCode = inviteCode.trimmingCharacters(in: .whitespaces)

        if trimmedInviteCode.isEmpty {
            inviteCodeError = "邀请码不能为空"
        }
        if trimmedUsername.count < 3 {
            usernameError = "用户名至少 3 位"
        }
        if !Self.isValidEmail(trimmedEmail) {
            emailError = "邮箱格式不正确"
        }
        if password.count < 8 {
            passwordError = "密码至少 8 位"
        }

        guard inviteCodeError == nil,
              usernameError == nil,
              emailError == nil,
              passwordError == nil else {
            state = .failed(.fieldValidation(field: nil, message: "客户端校验未通过"))
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
        } catch let error as AuthError {
            mapServerError(error)
            state = .failed(error)
        } catch {
            toast = "注册失败，请重试"
            state = .failed(.unknown(String(describing: error)))
        }
    }

    private func clearFieldErrors() {
        inviteCodeError = nil
        usernameError = nil
        emailError = nil
        passwordError = nil
        toast = nil
    }

    private func mapServerError(_ error: AuthError) {
        switch error {
        case .invalidInviteCode:
            // 设计文档要求邀请码错误既有字段红字，也要有 toast。
            inviteCodeError = "邀请码无效"
            toast = "邀请码无效"
        case .emailTaken:
            emailError = "邮箱已被注册"
        case .usernameTaken:
            usernameError = "用户名已被占用"
        case .fieldValidation(let field, let message):
            switch field {
            case .inviteCode:
                inviteCodeError = message
            case .username:
                usernameError = message
            case .email:
                emailError = message
            case .password:
                passwordError = message
            case .none:
                toast = message
            }
        case .network:
            toast = "网络错误，请检查连接"
        default:
            toast = "注册失败，请重试"
        }
    }

    nonisolated private static let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#

    nonisolated static func isValidEmail(_ string: String) -> Bool {
        string.range(of: emailRegex, options: .regularExpression) != nil
    }
}
