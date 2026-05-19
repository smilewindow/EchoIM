import Foundation
import SwiftData

/// 聊天缓存的组合清理入口：消息是大头；会话预览保留，只让分页边界失效。
@ModelActor
actor ChatCacheStore {
    func clearMessagesAndResetBounds() async throws {
        let messageCount = try modelContext.fetchCount(FetchDescriptor<CachedMessage>())
        try modelContext.delete(model: CachedMessage.self)

        let metas = try modelContext.fetch(FetchDescriptor<ConversationMeta>())
        for meta in metas {
            meta.oldestCachedMessageId = nil
            meta.newestCachedMessageId = nil
        }

        try modelContext.save()
        Log.info(
            .cache,
            "chat cache cleared: \(messageCount) messages, \(metas.count) metas reset"
        )
    }
}
