import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    enum State: Equatable {
        case idle
        case submitting
        case failed(AuthError)
        case success
    }

    var email = ""
    var password = ""
    var state: State = .idle
    /// 登录页错误统一走 toast，和设计文档里的交互保持一致。
    var toast: String?

    private let repo: AuthRepository
    private let onSuccess: (AuthResponse) -> Void

    init(repo: AuthRepository, onSuccess: @escaping (AuthResponse) -> Void) {
        self.repo = repo
        self.onSuccess = onSuccess
    }

    func submit() async {
        toast = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            let message = "邮箱和密码不能为空"
            toast = message
            state = .failed(.fieldValidation(field: nil, message: message))
            return
        }

        state = .submitting

        do {
            let response = try await repo.login(email: trimmedEmail, password: password)
            state = .success
            onSuccess(response)
        } catch let error as AuthError {
            state = .failed(error)
            toast = Self.toastMessage(for: error)
        } catch {
            state = .failed(.unknown(String(describing: error)))
            toast = "登录失败，请重试"
        }
    }

    nonisolated static func toastMessage(for error: AuthError) -> String {
        switch error {
        case .invalidCredentials:
            return "邮箱或密码错误"
        case .network:
            return "网络错误，请检查连接"
        case .fieldValidation(_, let message):
            return message
        default:
            return "登录失败，请重试"
        }
    }
}
