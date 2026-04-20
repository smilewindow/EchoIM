import Foundation

protocol FriendRequestRepository {
    func listIncoming(token: String) async throws -> [FriendRequest]
    func listSent(token: String) async throws -> [FriendRequest]
    func listHistory(token: String) async throws -> [FriendRequest]
    func send(recipientId: Int, token: String) async throws -> FriendRequest
    func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest
}

/// 这里显式映射 snake_case，请求体要和后端契约保持一致，避免把 camelCase 直接发出去。
private struct CreateFriendRequestBody: Encodable {
    let recipientId: Int

    enum CodingKeys: String, CodingKey {
        case recipientId = "recipient_id"
    }
}

private struct RespondBody: Encodable {
    let status: String
}

@MainActor
final class FriendRequestRepositoryImpl: FriendRequestRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func listIncoming(token: String) async throws -> [FriendRequest] {
        try await api.request(Endpoints.FriendRequests.base, token: token)
    }

    func listSent(token: String) async throws -> [FriendRequest] {
        try await api.request(Endpoints.FriendRequests.sent, token: token)
    }

    func listHistory(token: String) async throws -> [FriendRequest] {
        try await api.request(Endpoints.FriendRequests.history, token: token)
    }

    func send(recipientId: Int, token: String) async throws -> FriendRequest {
        try await api.request(
            Endpoints.FriendRequests.base,
            method: "POST",
            token: token,
            body: CreateFriendRequestBody(recipientId: recipientId)
        )
    }

    func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest {
        try await api.request(
            Endpoints.FriendRequests.respond(id: id),
            method: "PUT",
            token: token,
            body: RespondBody(status: accept ? "accepted" : "declined")
        )
    }
}
