import Foundation
import SwiftData

/// 落盘的消息实体。对齐 API `Message` 的所有字段；`clientTempId` 不存，
/// 它只服务于发送中的本地合并，再启动后没有业务价值。
@Model
final class CachedMessage {
    @Attribute(.unique) var id: Int
    var conversationId: Int
    var senderId: Int
    var body: String?
    var messageType: String
    var mediaUrl: String?
    var createdAt: Date

    init(
        id: Int,
        conversationId: Int,
        senderId: Int,
        body: String?,
        messageType: String,
        mediaUrl: String?,
        createdAt: Date
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.body = body
        self.messageType = messageType
        self.mediaUrl = mediaUrl
        self.createdAt = createdAt
    }

    /// @Model 不是 Sendable，出 actor 边界前统一转成普通值类型。
    func asMessage() -> Message {
        Message(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            body: body,
            messageType: messageType,
            mediaUrl: mediaUrl,
            createdAt: createdAt,
            clientTempId: nil
        )
    }
}
