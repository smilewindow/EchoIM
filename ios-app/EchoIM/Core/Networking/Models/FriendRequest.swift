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
}
