import Foundation

protocol UserRepository {
    func fetchMe(token: String) async throws -> AuthenticatedUser
    func searchUsers(query: String, token: String) async throws -> [UserProfile]
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
}
