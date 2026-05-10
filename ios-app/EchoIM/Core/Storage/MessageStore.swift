import Foundation
import SwiftData

/// 消息缓存的持久化入口。`CachedMessage` 不跨 actor 泄漏，调用方只收发 `Message`。
@ModelActor
actor MessageStore {
    /// 追加 confirmed 消息；重复 id 直接跳过，保证 REST/WS 重放时写入幂等。
    func append(_ messages: [Message]) async throws {
        guard !messages.isEmpty else { return }

        let incomingIds = messages.map(\.id)
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedMessage>(
                predicate: #Predicate<CachedMessage> { incomingIds.contains($0.id) }
            )
        )
        let existingIds = Set(existing.map(\.id))
        var seenIds = existingIds

        var insertedCount = 0
        for message in messages where !existingIds.contains(message.id) {
            guard seenIds.insert(message.id).inserted else {
                Log.debug(.cache, "message duplicate in batch skipped id=\(message.id)")
                continue
            }
            modelContext.insert(
                CachedMessage(
                    id: message.id,
                    conversationId: message.conversationId,
                    senderId: message.senderId,
                    body: message.body,
                    messageType: message.messageType,
                    mediaUrl: message.mediaUrl,
                    mediaWidth: message.mediaWidth,
                    mediaHeight: message.mediaHeight,
                    createdAt: message.createdAt
                )
            )
            insertedCount += 1
        }

        try modelContext.save()
        let skippedCount = messages.count - insertedCount
        Log.debug(.cache, "messages appended: \(insertedCount) inserted, \(skippedCount) skipped")
    }

    /// 返回最新 `limit` 条，排序保持服务端分页契约：DESC，最新在前。
    func loadLatest(conversationId: Int, limit: Int) async throws -> [Message] {
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate<CachedMessage> { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let messages = try modelContext.fetch(descriptor).map { $0.asMessage() }
        Log.debug(.cache, "messages loadLatest c=\(conversationId) limit=\(limit) hit=\(messages.count)")
        return messages
    }

    /// 返回 `id < before` 的更老消息，DESC，最多 `limit` 条。
    func loadOlder(conversationId: Int, before: Int, limit: Int) async throws -> [Message] {
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate<CachedMessage> {
                $0.conversationId == conversationId && $0.id < before
            },
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let messages = try modelContext.fetch(descriptor).map { $0.asMessage() }
        Log.debug(.cache, "messages loadOlder c=\(conversationId) before=\(before) hit=\(messages.count)")
        return messages
    }

    /// 清空所有会话消息。用于 Me 页清缓存和登出前释放。
    func deleteAll() async throws {
        let descriptor = FetchDescriptor<CachedMessage>()
        let rows = try modelContext.fetch(descriptor)
        for row in rows { modelContext.delete(row) }
        try modelContext.save()
        let deletedCount = rows.count
        Log.info(.cache, "messages cleared (\(deletedCount) rows)")
    }
}
