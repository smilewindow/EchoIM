import UIKit

/// 与服务端消息图片配置对齐：长边 1600、JPEG 0.80、透明像素落白底。
enum ImageCompressor {
    /// 返回 nil 表示编码失败；调用方按发送失败或静默放弃处理。
    static func compressForUpload(_ image: UIImage) -> (data: Data, width: Int, height: Int)? {
        let maxDim: CGFloat = 1600
        let scale = min(1.0, maxDim / max(image.size.width, image.size.height))
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let format = UIGraphicsImageRendererFormat.default()
        // opaque + scale=1 避免透明图落黑底，也避免 @2x/@3x 把 1600pt 放大成更多像素。
        format.opaque = true
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = resized.jpegData(compressionQuality: 0.80) else {
            return nil
        }

        return (data, Int(targetSize.width), Int(targetSize.height))
    }
}
