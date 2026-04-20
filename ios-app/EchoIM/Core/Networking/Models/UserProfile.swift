import Foundation

/// 只读用户摘要，供好友、搜索结果、会话对端等场景复用。
/// 已登录用户自己的完整资料仍然使用 `AuthenticatedUser`。
struct UserProfile: Codable, Identifiable, Equatable, Sendable, Hashable {
    let id: Int
    let username: String
    let displayName: String?
    let avatarUrl: String?
}
