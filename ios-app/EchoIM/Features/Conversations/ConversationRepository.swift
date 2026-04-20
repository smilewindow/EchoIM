import Foundation

protocol ConversationRepository {
    func list(token: String) async throws -> [Conversation]
}

@MainActor
final class ConversationRepositoryImpl: ConversationRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(token: String) async throws -> [Conversation] {
        try await api.request(Endpoints.Conversations.list, token: token)
    }
}
