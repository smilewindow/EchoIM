import ImageIO
import UIKit

struct ImageCompressionResult: Sendable, Equatable {
    let data: Data
    let width: Int
    let height: Int
}

struct PreparedMessageImage: Sendable, Equatable {
    let upload: ImageCompressionResult
    let previewData: Data?
}

/// 与服务端消息图片配置对齐：长边 1600、JPEG 0.80、透明像素落白底。
enum ImageCompressor {
    nonisolated private static let uploadMaxPixelSize = 1600
    nonisolated private static let uploadJPEGQuality = 0.80
    nonisolated private static let previewMaxPixelSize = 720
    nonisolated private static let previewJPEGQuality = 0.75
    nonisolated(unsafe) private static let jpegUTI = "public.jpeg" as CFString

    /// 返回 nil 表示编码失败；调用方按发送失败或静默放弃处理。
    static func compressForUpload(_ image: UIImage) -> ImageCompressionResult? {
        let maxDim = CGFloat(uploadMaxPixelSize)
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

        guard let data = resized.jpegData(compressionQuality: uploadJPEGQuality) else {
            return nil
        }

        return ImageCompressionResult(data: data, width: Int(targetSize.width), height: Int(targetSize.height))
    }

    nonisolated static func prepareForMessageImage(data: Data) async -> PreparedMessageImage? {
        let uploadMaxPixelSize = Self.uploadMaxPixelSize
        let uploadJPEGQuality = Self.uploadJPEGQuality
        let previewMaxPixelSize = Self.previewMaxPixelSize
        let previewJPEGQuality = Self.previewJPEGQuality
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let uploadImage = makeThumbnail(from: source, maxPixelSize: uploadMaxPixelSize),
                  let uploadData = encodeJPEG(uploadImage, jpegQuality: uploadJPEGQuality) else {
                return nil
            }

            let previewImage = resize(uploadImage, maxPixelSize: previewMaxPixelSize)
            let previewData = previewImage.flatMap {
                encodeJPEG($0, jpegQuality: previewJPEGQuality)
            }

            return PreparedMessageImage(
                upload: ImageCompressionResult(
                    data: uploadData,
                    width: uploadImage.width,
                    height: uploadImage.height
                ),
                previewData: previewData
            )
        }.value
    }

    nonisolated private static func makeThumbnail(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> CGImage? {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }

        return flattenOnWhiteBackground(thumbnail)
    }

    nonisolated private static func encodeJPEG(_ image: CGImage, jpegQuality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            jpegUTI,
            1,
            nil
        ) else {
            return nil
        }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return output as Data
    }

    nonisolated private static func resize(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxPixelSize else {
            return image
        }

        let scale = CGFloat(maxPixelSize) / CGFloat(longEdge)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    nonisolated private static func flattenOnWhiteBackground(_ image: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
