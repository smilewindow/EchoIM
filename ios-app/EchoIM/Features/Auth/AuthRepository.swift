import Foundation

enum RegisterField: String, Equatable, Sendable {
    case inviteCode
    case username
    case email
    case password
}

enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case invalidInviteCode
    case emailTaken
    case usernameTaken
    /// `field == nil` 代表服务端返回了 400，但无法定位到具体字段，交给 View 走 toast。
    case fieldValidation(field: RegisterField?, message: String)
    case network
    case unknown(String)
}

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
        do {
            let response: AuthResponse = try await api.request(
                Endpoints.Auth.login,
                method: "POST",
                body: LoginRequest(email: email, password: password)
            )
            try tokenStore.save(token: response.token, userId: response.user.id)
            return response
        } catch let error as APIError {
            throw Self.mapLoginError(error)
        }
    }

    func register(_ request: RegisterRequest) async throws -> AuthResponse {
        do {
            let response: AuthResponse = try await api.request(
                Endpoints.Auth.register,
                method: "POST",
                body: request
            )
            try tokenStore.save(token: response.token, userId: response.user.id)
            return response
        } catch let error as APIError {
            throw Self.mapRegisterError(error)
        }
    }

    func logout() async {
        try? tokenStore.clear()
    }

    nonisolated static func mapLoginError(_ error: APIError) -> AuthError {
        switch error {
        case .unauthorized:
            return .invalidCredentials
        case .network:
            return .network
        case .decoding(let message):
            return .unknown(message)
        case .invalidResponse:
            return .unknown("invalid response")
        case .http(let status, let body):
            let message = Self.extractErrorMessage(body)
            return .unknown("\(status): \(message)")
        }
    }

    nonisolated static func mapRegisterError(_ error: APIError) -> AuthError {
        guard case .http(let status, let body) = error else {
            if case .network = error {
                return .network
            }
            return .unknown(String(describing: error))
        }

        let message = Self.extractErrorMessage(body)
        let lowerMessage = message.lowercased()

        switch status {
        case 403 where lowerMessage.contains("invite"):
            return .invalidInviteCode
        case 409 where lowerMessage.contains("email"):
            return .emailTaken
        case 409 where lowerMessage.contains("username"):
            return .usernameTaken
        case 400:
            return .fieldValidation(field: Self.detectField(lowerMessage), message: message)
        default:
            return .unknown("\(status): \(message)")
        }
    }

    /// 这里优先识别 `inviteCode`，避免后续如果消息里既带 invite 又带其它通用词时落错字段。
    nonisolated static func detectField(_ lowerMessage: String) -> RegisterField? {
        if lowerMessage.contains("invitecode")
            || lowerMessage.contains("invite code")
            || lowerMessage.contains("invite") {
            return .inviteCode
        }
        if lowerMessage.contains("username") {
            return .username
        }
        if lowerMessage.contains("email") {
            return .email
        }
        if lowerMessage.contains("password") {
            return .password
        }
        return nil
    }

    nonisolated private static func extractErrorMessage(_ body: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let message = object["error"] as? String {
            return message
        }

        return String(data: body, encoding: .utf8) ?? ""
    }
}
