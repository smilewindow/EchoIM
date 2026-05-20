import Foundation

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// 注册接口要求 camelCase 的 `inviteCode`，因此这里保持默认键名，不做全局 snake_case 编码。
struct RegisterRequest: Encodable {
    let username: String
    let email: String
    let password: String
    let inviteCode: String
}

protocol AuthRepository {
    func login(email: String, password: String) async throws -> AuthResponse
    func register(_ request: RegisterRequest) async throws -> AuthResponse
    func logout() async
}

@MainActor
final class AuthRepositoryImpl: AuthRepository {
    private let api: APIClient
    private let tokenStore: KeychainTokenStore

    init(api: APIClient, tokenStore: KeychainTokenStore) {
        self.api = api
        self.tokenStore = tokenStore
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await api.request(
            Endpoints.Auth.login,
            method: "POST",
            body: LoginRequest(email: email, password: password)
        )
        try tokenStore.save(token: response.token, userId: response.user.id)
        return response
    }

    func register(_ request: RegisterRequest) async throws -> AuthResponse {
        let response: AuthResponse = try await api.request(
            Endpoints.Auth.register,
            method: "POST",
            body: request
        )
        try tokenStore.save(token: response.token, userId: response.user.id)
        return response
    }

    func logout() async {
        try? tokenStore.clear()
    }
}
