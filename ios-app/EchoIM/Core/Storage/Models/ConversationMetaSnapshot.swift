import Foundation

/// `ConversationMeta` 的 Sendable 值类型镜像。ViewModel / Repository 只碰这个，
/// 不把 SwiftData `@Model` 本体跨 actor 传出去。
struct ConversationMetaSnapshot: Sendable, Equatable {
    let conversationId: Int
    let peerUserId: Int
    let peerUsername: String
    let peerDisplayName: String?
    let peerAvatarUrl: String?
    let oldestCachedMessageId: Int?
    let newestCachedMessageId: Int?
    let lastReadMessageId: Int?
    let unreadCount: Int
    let lastMessageBody: String?
    let lastMessageType: String?
    let lastMessageAt: Date?
}
