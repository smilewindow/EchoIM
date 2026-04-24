import Foundation
import SwiftData

/// 消息缓存的持久化入口。`CachedMessage` 不跨 actor 泄漏，调用方只收发 `Message`。
@ModelActor
actor MessageStore {
    /// 追加 confirmed 消息；重复 id 直接跳过，保证 REST/WS 重放时写入幂等。
    func append(_ messages: [Message]) async throws {
        guard !messages.isEmpty else { return }

        for message in messages {
            let id = message.id
            var descriptor = FetchDescriptor<CachedMessage>(
                predicate: #Predicate<CachedMessage> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if try modelContext.fetch(descriptor).first != nil {
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
                    createdAt: message.createdAt
                )
            )
        }

        try modelContext.save()
    }

    /// 返回最新 `limit` 条，排序保持服务端分页契约：DESC，最新在前。
    func loadLatest(conversationId: Int, limit: Int) async throws -> [Message] {
        var descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate<CachedMessage> { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { $0.asMessage() }
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
        return try modelContext.fetch(descriptor).map { $0.asMessage() }
    }

    /// 清空所有会话消息。用于 Me 页清缓存和登出前释放。
    func deleteAll() async throws {
        let descriptor = FetchDescriptor<CachedMessage>()
        for row in try modelContext.fetch(descriptor) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }
}
