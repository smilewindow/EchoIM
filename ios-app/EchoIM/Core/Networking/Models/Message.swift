import Foundation

/// 一条消息（服务端原样）。`clientTempId` 仅对发送者自己的那条存在，
/// 用于乐观发送去重（见 ChatViewModel.send）；不持久化。
struct Message: Codable, Identifiable, Equatable, Sendable, Hashable {
    let id: Int
    let conversationId: Int
    let senderId: Int
    let body: String?
    let messageType: String
    let mediaUrl: String?
    let createdAt: Date
    let clientTempId: String?
}
