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
    /// 服务端在上传时提取的图片像素尺寸；老消息可能为 nil，客户端按 4:3 兜底。
    let mediaWidth: Int?
    let mediaHeight: Int?
    let createdAt: Date
    let clientTempId: String?

    /// 显式 init 让 mediaWidth/Height 可省略，老的构造点（含测试）无需改造；
    /// JSON 解码走 synthesized Codable，缺字段自动 nil。
    init(
        id: Int,
        conversationId: Int,
        senderId: Int,
        body: String?,
        messageType: String,
        mediaUrl: String?,
        mediaWidth: Int? = nil,
        mediaHeight: Int? = nil,
        createdAt: Date,
        clientTempId: String?
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.body = body
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.mediaWidth = mediaWidth
        self.mediaHeight = mediaHeight
        self.createdAt = createdAt
        self.clientTempId = clientTempId
    }
}
