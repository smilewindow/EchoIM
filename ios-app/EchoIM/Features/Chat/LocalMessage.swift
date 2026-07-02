import Foundation
import UIKit

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
    var localImageData: Data? {
        didSet {
            localImage = Self.decodeBubblePreview(localImageData)
        }
    }

    var id: String { localId }

    private(set) var localImage: UIImage?

    init(
        localId: String,
        message: Message,
        sendState: MessageSendState,
        localImageData: Data?
    ) {
        self.localId = localId
        self.message = message
        self.sendState = sendState
        self.localImageData = localImageData
        self.localImage = Self.decodeBubblePreview(localImageData)
    }

    /// 气泡只有 220pt 宽，按 previewMaxPixelSize 降采样解码；
    /// 直接 UIImage(data:) 会把相册原图整幅解出来，pending 期间产生大内存尖峰。
    /// Lightbox 放大查看拿的是 localImageData 原始数据，不受影响。
    private static func decodeBubblePreview(_ data: Data?) -> UIImage? {
        data.flatMap {
            ImageCompressor.decodeThumbnail(from: $0, maxPixelSize: ImageCompressor.previewMaxPixelSize)
        }
    }

    static func == (lhs: LocalMessage, rhs: LocalMessage) -> Bool {
        lhs.localId == rhs.localId &&
            lhs.message == rhs.message &&
            lhs.sendState == rhs.sendState &&
            lhs.localImageData == rhs.localImageData
    }

    static func confirmed(_ message: Message) -> LocalMessage {
        LocalMessage(
            localId: "id-\(message.id)",
            message: message,
            sendState: .confirmed,
            localImageData: nil
        )
    }
}
