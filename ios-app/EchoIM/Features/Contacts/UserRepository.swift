import Foundation

protocol UserRepository {
    func fetchMe(token: String) async throws -> AuthenticatedUser
    func searchUsers(query: String, token: String) async throws -> [UserProfile]
    /// P7：单字段更新 displayName。avatar_url 不通过这个端点改（见不变式 1 / 2）。
    func updateProfile(displayName: String, token: String) async throws -> AuthenticatedUser
}

/// 服务端 `PUT /api/users/me` 接收 snake_case 字段名，所以在这里显式 CodingKey。
private struct UpdateProfileRequest: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

@MainActor
final class UserRepositoryImpl: UserRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func fetchMe(token: String) async throws -> AuthenticatedUser {
        try await api.request(Endpoints.Users.me, token: token)
    }

    func searchUsers(query: String, token: String) async throws -> [UserProfile] {
        var components = URLComponents()
        components.path = Endpoints.Users.search
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        let path = components.path + "?" + (components.percentEncodedQuery ?? "")
        return try await api.request(path, token: token)
    }

    func updateProfile(displayName: String, token: String) async throws -> AuthenticatedUser {
        try await api.request(
            Endpoints.Users.me,
            method: "PUT",
            token: token,
            body: UpdateProfileRequest(displayName: displayName)
        )
    }
}
