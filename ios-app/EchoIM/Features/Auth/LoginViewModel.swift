import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    enum State: Equatable {
        case idle
        case submitting
        case failed
        case success
    }

    var email = ""
    var password = ""
    var state: State = .idle

    private let repo: AuthRepository
    private let onSuccess: (AuthResponse) -> Void
    private var onError: @MainActor (Error) -> Void
    private var onToast: @MainActor (String) -> Void

    init(
        repo: AuthRepository,
        onSuccess: @escaping (AuthResponse) -> Void,
        onError: @escaping @MainActor (Error) -> Void = { _ in },
        onToast: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.repo = repo
        self.onSuccess = onSuccess
        self.onError = onError
        self.onToast = onToast
    }

    func setOnErrorHandler(_ handler: @escaping @MainActor (Error) -> Void) {
        onError = handler
    }

    func setOnToastHandler(_ handler: @escaping @MainActor (String) -> Void) {
        onToast = handler
    }

    func submit() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            state = .failed
            onToast(String(localized: "邮箱和密码不能为空"))
            return
        }

        state = .submitting

        do {
            let response = try await repo.login(email: trimmedEmail, password: password)
            state = .success
            onSuccess(response)
        } catch APIError.unauthorized {
            state = .failed
            onToast(String(localized: "邮箱或密码错误"))
        } catch {
            state = .failed
            onError(error)
        }
    }
}
