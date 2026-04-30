import Foundation

/// 图片消息阶段化重试状态：
/// - notStarted：尚未上传成功，重试要从上传开始。
/// - uploaded：上传已成功，重试可跳过上传，直接用缓存的 url + 尺寸发消息。
enum ImageSendStage: Sendable, Equatable {
    case notStarted
    case uploaded(mediaURL: String, mediaWidth: Int, mediaHeight: Int)
}
