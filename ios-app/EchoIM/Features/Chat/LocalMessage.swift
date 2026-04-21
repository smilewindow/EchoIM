import Foundation

enum MessageSendState: Equatable, Sendable {
    case confirmed
    case pending
    case failed(String)
}

/// ChatViewModel 持有的消息状态。一条消息的身份有两个可能 key：
/// - 已确认消息：`message.id`
/// - 草稿/pending：`localId`（客户端生成的 UUID 字符串，对应 `clientTempId`）
///
/// `localImageData` P3 不用，先作为 P5 图片消息的本地预览预留字段。
struct LocalMessage: Identifiable, Equatable, Sendable {
    let localId: String
    var message: Message
    var sendState: MessageSendState
    var localImageData: Data?

    var id: String { localId }

    static func confirmed(_ message: Message) -> LocalMessage {
        LocalMessage(
            localId: "id-\(message.id)",
            message: message,
            sendState: .confirmed,
            localImageData: nil
        )
    }
}
