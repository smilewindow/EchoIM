import UIKit

/// 与服务端 AVATAR_CONFIG 对齐：cover-fit 居中裁剪到 400×400、白底 flatten、JPEG 0.80。
/// 与 ImageCompressor（消息图 1600px fit-inside）刻意分开（不变式 9）。
enum AvatarImageCompressor {
    static let outputSize: CGFloat = 400
    static let jpegQuality: CGFloat = 0.80

    /// 返回 nil 表示编码失败；调用方按上传失败处理。
    static func compressForUpload(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let target = CGSize(width: outputSize, height: outputSize)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                   // 物理像素就是 outputSize；不要按 @2x/@3x 放大
        format.opaque = true               // 白底 + JPEG 编码（不要 alpha 通道）

        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let cropped = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))

            // cover-fit 居中：先按"短边铺满 400"等比缩放，多余的两侧/上下被画布裁掉。
            let imgSize = image.size
            let scale = max(target.width / imgSize.width, target.height / imgSize.height)
            let scaled = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let origin = CGPoint(
                x: (target.width - scaled.width) / 2,
                y: (target.height - scaled.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: scaled))
        }

        return cropped.jpegData(compressionQuality: jpegQuality)
    }
}
