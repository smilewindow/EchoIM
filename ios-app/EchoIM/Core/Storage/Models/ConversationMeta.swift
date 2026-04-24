import Foundation
import SwiftData

/// 每个会话一条元数据：记录本地连续后缀边界，以及会话列表冷启动预览所需字段。
@Model
final class ConversationMeta {
    @Attribute(.unique) var conversationId: Int

    /// 本地缓存中最旧一条消息的 id；nil 表示缓存还没有命中过。
    var oldestCachedMessageId: Int?
    /// 本地缓存中最新一条消息的 id；nil 表示缓存为空。
    var newestCachedMessageId: Int?
    /// 本地已记录的已读上限。
    var lastReadMessageId: Int?
    /// 冷启动先展示的未读数，后续会被服务端刷新覆盖。
    var unreadCount: Int

    var lastMessageBody: String?
    var lastMessageType: String?
    var lastMessageAt: Date?

    /// 会话列表离线渲染必须有真实 peer 摘要，不能退成空占位。
    var peerUserId: Int
    var peerUsername: String
    var peerDisplayName: String?
    var peerAvatarUrl: String?

    init(
        conversationId: Int,
        peerUserId: Int,
        peerUsername: String,
        peerDisplayName: String? = nil,
        peerAvatarUrl: String? = nil,
        oldestCachedMessageId: Int? = nil,
        newestCachedMessageId: Int? = nil,
        lastReadMessageId: Int? = nil,
        unreadCount: Int = 0,
        lastMessageBody: String? = nil,
        lastMessageType: String? = nil,
        lastMessageAt: Date? = nil
    ) {
        self.conversationId = conversationId
        self.peerUserId = peerUserId
        self.peerUsername = peerUsername
        self.peerDisplayName = peerDisplayName
        self.peerAvatarUrl = peerAvatarUrl
        self.oldestCachedMessageId = oldestCachedMessageId
        self.newestCachedMessageId = newestCachedMessageId
        self.lastReadMessageId = lastReadMessageId
        self.unreadCount = unreadCount
        self.lastMessageBody = lastMessageBody
        self.lastMessageType = lastMessageType
        self.lastMessageAt = lastMessageAt
    }

    func snapshot() -> ConversationMetaSnapshot {
        ConversationMetaSnapshot(
            conversationId: conversationId,
            peerUserId: peerUserId,
            peerUsername: peerUsername,
            peerDisplayName: peerDisplayName,
            peerAvatarUrl: peerAvatarUrl,
            oldestCachedMessageId: oldestCachedMessageId,
            newestCachedMessageId: newestCachedMessageId,
            lastReadMessageId: lastReadMessageId,
            unreadCount: unreadCount,
            lastMessageBody: lastMessageBody,
            lastMessageType: lastMessageType,
            lastMessageAt: lastMessageAt
        )
    }
}
