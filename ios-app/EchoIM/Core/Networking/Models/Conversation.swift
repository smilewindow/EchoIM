import Foundation

/// 一对一会话。服务端返回的是扁平 peer_* 字段，这里统一聚合成 UserProfile，
/// 这样 ViewModel 和视图层只面对稳定的嵌套结构。
struct Conversation: Identifiable, Equatable, Sendable, Hashable {
    let id: Int
    let createdAt: Date
    let peer: UserProfile
    let lastMessageBody: String?
    let lastMessageType: String?
    let lastMessageSenderId: Int?
    let lastMessageAt: Date?
    let lastReadMessageId: Int?
    let unreadCount: Int
}

extension Conversation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case peerId
        case peerUsername
        case peerDisplayName
        case peerAvatarUrl
        case lastMessageBody
        case lastMessageType
        case lastMessageSenderId
        case lastMessageAt
        case lastReadMessageId
        case unreadCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        peer = UserProfile(
            id: try container.decode(Int.self, forKey: .peerId),
            username: try container.decode(String.self, forKey: .peerUsername),
            displayName: try container.decodeIfPresent(String.self, forKey: .peerDisplayName),
            avatarUrl: try container.decodeIfPresent(String.self, forKey: .peerAvatarUrl)
        )
        lastMessageBody = try container.decodeIfPresent(String.self, forKey: .lastMessageBody)
        lastMessageType = try container.decodeIfPresent(String.self, forKey: .lastMessageType)
        lastMessageSenderId = try container.decodeIfPresent(Int.self, forKey: .lastMessageSenderId)
        lastMessageAt = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        lastReadMessageId = try container.decodeIfPresent(Int.self, forKey: .lastReadMessageId)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
    }
}
