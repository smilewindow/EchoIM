import Foundation

enum FriendRequestStatus: String, Codable, Equatable, Sendable {
    case pending
    case accepted
    case declined
}

struct FriendRequest: Identifiable, Equatable, Decodable, Sendable {
    let id: Int
    let senderId: Int
    let recipientId: Int
    let status: FriendRequestStatus
    let createdAt: Date
    let updatedAt: Date?
    /// `/history` 会返回当前用户视角下的方向；其它接口没有这个字段。
    let direction: String?
    /// 联表出来的对方用户摘要。POST / PUT 直接返回表行时，这些字段不存在。
    let username: String?
    let displayName: String?
    let avatarUrl: String?

    /// 好友申请里的用户摘要可能来自联表，也可能在刚 POST/PUT 后暂缺。
    func displayTitle(fallback: String = "用户") -> String {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDisplayName?.isEmpty == false {
            return trimmedDisplayName!
        }

        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername?.isEmpty == false {
            return trimmedUsername!
        }

        return fallback
    }

    var usernameSubtitle: String? {
        guard let username = username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty,
              displayTitle() != username
        else {
            return nil
        }

        return "@\(username)"
    }
}
