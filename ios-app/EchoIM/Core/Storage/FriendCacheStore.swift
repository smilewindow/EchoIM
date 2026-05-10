import Foundation
import SwiftData

/// 好友列表本地缓存，冷启动时补位，替换已失去好友关系的记录。
@ModelActor
actor FriendCacheStore {
    /// 替换整个好友列表：删除已不是好友的旧条目，upsert 当前列表。
    func saveAll(_ friends: [UserProfile]) throws {
        let currentIds = Set(friends.map(\.id))

        let existing = try modelContext.fetch(FetchDescriptor<CachedFriend>())
        let staleRows = existing.filter { !currentIds.contains($0.userId) }
        for row in staleRows { modelContext.delete(row) }

        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.userId, $0) })
        for friend in friends {
            if let row = existingById[friend.id] {
                row.username = friend.username
                row.displayName = friend.displayName
                row.avatarUrl = friend.avatarUrl
            } else {
                modelContext.insert(
                    CachedFriend(
                        userId: friend.id,
                        username: friend.username,
                        displayName: friend.displayName,
                        avatarUrl: friend.avatarUrl
                    )
                )
            }
        }

        try modelContext.save()
        let removedCount = staleRows.count
        Log.debug(.cache, "friends synced: \(friends.count) current, \(removedCount) removed")
    }

    func loadAll() throws -> [UserProfile] {
        let descriptor = FetchDescriptor<CachedFriend>(
            sortBy: [SortDescriptor(\.username)]
        )
        let friends = try modelContext.fetch(descriptor).map { $0.toUserProfile() }
        Log.debug(.cache, "friends loadAll hit=\(friends.count)")
        return friends
    }

    func deleteAll() throws {
        let all = try modelContext.fetch(FetchDescriptor<CachedFriend>())
        for row in all { modelContext.delete(row) }
        try modelContext.save()
        let deletedCount = all.count
        Log.info(.cache, "friends cleared (\(deletedCount) rows)")
    }
}
