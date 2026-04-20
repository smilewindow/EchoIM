import Foundation

protocol FriendRepository {
    func list(token: String) async throws -> [Friend]
}

@MainActor
final class FriendRepositoryImpl: FriendRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(token: String) async throws -> [Friend] {
        try await api.request(Endpoints.Friends.list, token: token)
    }
}
