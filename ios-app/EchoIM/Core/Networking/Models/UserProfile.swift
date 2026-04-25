import Foundation

/// 只读用户摘要，供好友、搜索结果、会话对端等场景复用。
/// 已登录用户自己的完整资料仍然使用 `AuthenticatedUser`。
struct UserProfile: Codable, Identifiable, Equatable, Sendable, Hashable {
    let id: Int
    let username: String
    let displayName: String?
    let avatarUrl: String?

    /// UI 展示名：displayName 为空字符串时也回退到 username，避免列表出现“空标题”。
    var displayTitle: String {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDisplayName?.isEmpty == false ? trimmedDisplayName! : username
    }

    /// 只有 displayName 真正承担主标题时，副标题才显示 @username，减少重复信息。
    var usernameSubtitle: String? {
        displayTitle == username ? nil : "@\(username)"
    }
}
