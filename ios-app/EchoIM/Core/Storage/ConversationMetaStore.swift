import Foundation
import SwiftData

/// 会话元数据缓存入口，维护消息连续后缀边界和会话列表冷启动预览。
@ModelActor
actor ConversationMetaStore {
    func upsert(_ snapshot: ConversationMetaSnapshot) async throws {
        let conversationId = snapshot.conversationId
        var descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate<ConversationMeta> { $0.conversationId == conversationId }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.peerUserId = snapshot.peerUserId
            existing.peerUsername = snapshot.peerUsername
            existing.peerDisplayName = snapshot.peerDisplayName
            existing.peerAvatarUrl = snapshot.peerAvatarUrl
            existing.oldestCachedMessageId = snapshot.oldestCachedMessageId
            existing.newestCachedMessageId = snapshot.newestCachedMessageId
            existing.lastReadMessageId = snapshot.lastReadMessageId
            existing.unreadCount = snapshot.unreadCount
            existing.lastMessageBody = snapshot.lastMessageBody
            existing.lastMessageType = snapshot.lastMessageType
            existing.lastMessageAt = snapshot.lastMessageAt
        } else {
            modelContext.insert(
                ConversationMeta(
                    conversationId: snapshot.conversationId,
                    peerUserId: snapshot.peerUserId,
                    peerUsername: snapshot.peerUsername,
                    peerDisplayName: snapshot.peerDisplayName,
                    peerAvatarUrl: snapshot.peerAvatarUrl,
                    oldestCachedMessageId: snapshot.oldestCachedMessageId,
                    newestCachedMessageId: snapshot.newestCachedMessageId,
                    lastReadMessageId: snapshot.lastReadMessageId,
                    unreadCount: snapshot.unreadCount,
                    lastMessageBody: snapshot.lastMessageBody,
                    lastMessageType: snapshot.lastMessageType,
                    lastMessageAt: snapshot.lastMessageAt
                )
            )
        }

        try modelContext.save()
    }

    func loadByPeerUserId(_ peerUserId: Int) async throws -> ConversationMetaSnapshot? {
        var descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate<ConversationMeta> { $0.peerUserId == peerUserId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.snapshot()
    }

    func load(conversationId: Int) async throws -> ConversationMetaSnapshot? {
        var descriptor = FetchDescriptor<ConversationMeta>(
            predicate: #Predicate<ConversationMeta> { $0.conversationId == conversationId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.snapshot()
    }

    /// 会话列表冷启动用，按最后消息时间倒序；没有最后消息的会话自然排到后面。
    func loadAll() async throws -> [ConversationMetaSnapshot] {
        let descriptor = FetchDescriptor<ConversationMeta>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { $0.snapshot() }
    }

    func deleteAll() async throws {
        let descriptor = FetchDescriptor<ConversationMeta>()
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }
}
