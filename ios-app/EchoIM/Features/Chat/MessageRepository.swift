import Foundation

/// 消息分页游标。服务端用全局 SERIAL ID，所以 cursor 是 Int。
enum MessageCursor: Equatable, Sendable {
    case before(Int)   // ?before=<id>：取比该 id 小的，DESC 50 条
    case after(Int)    // ?after=<id>：取比该 id 大的，ASC 50 条
}

protocol MessageRepository {
    /// 无 cursor → 最新 50 条（DESC）
    /// .before → 更早 50 条（DESC）
    /// .after → 更新 50 条（ASC）
    func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message]
    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message
    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws
}

private struct SendTextBody: Encodable {
    let recipientId: Int
    let body: String
    let clientTempId: String

    enum CodingKeys: String, CodingKey {
        case recipientId = "recipient_id"
        case body
        case clientTempId = "client_temp_id"
    }
}

private struct MarkReadBody: Encodable {
    let lastReadMessageId: Int

    enum CodingKeys: String, CodingKey {
        case lastReadMessageId = "last_read_message_id"
    }
}

@MainActor
final class MessageRepositoryImpl: MessageRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func list(conversationId: Int, cursor: MessageCursor?, token: String) async throws -> [Message] {
        var comps = URLComponents()
        comps.path = Endpoints.Conversations.messages(conversationId: conversationId)
        switch cursor {
        case .before(let id):
            comps.queryItems = [URLQueryItem(name: "before", value: String(id))]
        case .after(let id):
            comps.queryItems = [URLQueryItem(name: "after", value: String(id))]
        case nil:
            break
        }
        let path = comps.path + (comps.percentEncodedQuery.map { "?" + $0 } ?? "")
        return try await api.request(path, token: token)
    }

    func sendText(
        recipientId: Int,
        body: String,
        clientTempId: String,
        token: String
    ) async throws -> Message {
        try await api.request(
            Endpoints.Messages.base,
            method: "POST",
            token: token,
            body: SendTextBody(recipientId: recipientId, body: body, clientTempId: clientTempId)
        )
    }

    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {
        let _: EmptyResponse = try await api.request(
            Endpoints.Conversations.read(conversationId: conversationId),
            method: "PUT",
            token: token,
            body: MarkReadBody(lastReadMessageId: lastReadMessageId)
        )
    }
}
