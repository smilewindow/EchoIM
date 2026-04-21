import Foundation

/// 服务端推送的业务事件。`connection.ready` 不放进来——它是 WebSocketClient 内部
/// 握手信号（.handshaking → .ready），不分发给业务订阅者。
/// 遇到未识别 type 时落到 `.unknown(type)`，避免整条 WS 连接因未来协议演进而死。
enum WSEvent: Decodable, Equatable, Sendable {
    case messageNew(Message)
    case conversationUpdated(ConversationUpdatedPayload)
    case typingStart(ConversationUserPayload)
    case typingStop(ConversationUserPayload)
    case presenceOnline(UserIdPayload)
    case presenceOffline(UserIdPayload)
    case friendRequestNew(FriendRequest)
    case friendRequestAccepted(FriendRequest)
    case friendRequestDeclined(FriendRequest)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message.new":
            self = .messageNew(try container.decode(Message.self, forKey: .payload))
        case "conversation.updated":
            self = .conversationUpdated(
                try container.decode(ConversationUpdatedPayload.self, forKey: .payload)
            )
        case "typing.start":
            self = .typingStart(try container.decode(ConversationUserPayload.self, forKey: .payload))
        case "typing.stop":
            self = .typingStop(try container.decode(ConversationUserPayload.self, forKey: .payload))
        case "presence.online":
            self = .presenceOnline(try container.decode(UserIdPayload.self, forKey: .payload))
        case "presence.offline":
            self = .presenceOffline(try container.decode(UserIdPayload.self, forKey: .payload))
        case "friend_request.new":
            self = .friendRequestNew(try container.decode(FriendRequest.self, forKey: .payload))
        case "friend_request.accepted":
            self = .friendRequestAccepted(try container.decode(FriendRequest.self, forKey: .payload))
        case "friend_request.declined":
            self = .friendRequestDeclined(try container.decode(FriendRequest.self, forKey: .payload))
        default:
            self = .unknown(type)
        }
    }
}

struct ConversationUpdatedPayload: Decodable, Equatable, Sendable {
    let conversationId: Int
    let lastReadMessageId: Int
}

struct ConversationUserPayload: Decodable, Equatable, Sendable {
    let conversationId: Int
    let userId: Int
}

struct UserIdPayload: Decodable, Equatable, Sendable {
    let userId: Int
}
