import Observation

@MainActor
@Observable
final class AuthFlowViewModel {
    var login: LoginViewModel
    var register: RegisterViewModel

    private let makeRepository: () -> AuthRepository
    private let onSuccess: (AuthResponse) -> Void

    init(
        makeRepository: @escaping () -> AuthRepository,
        onSuccess: @escaping (AuthResponse) -> Void
    ) {
        self.makeRepository = makeRepository
        self.onSuccess = onSuccess
        self.login = LoginViewModel(repo: makeRepository(), onSuccess: onSuccess)
        self.register = RegisterViewModel(repo: makeRepository(), onSuccess: onSuccess)
    }

    func reset() {
        login = LoginViewModel(repo: makeRepository(), onSuccess: onSuccess)
        register = RegisterViewModel(repo: makeRepository(), onSuccess: onSuccess)
    }
}
