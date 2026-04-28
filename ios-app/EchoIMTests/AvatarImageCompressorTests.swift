import Foundation
import Testing
import UIKit
@testable import EchoIM

@MainActor
@Suite("AvatarImageCompressor")
struct AvatarImageCompressorTests {
    @Test
    func landscapeImageIsCenterCroppedToSquare() throws {
        // 800×400 横向图 → 期望中心裁出 400×400，再缩到 400×400（无缩放）
        let landscape = Self.makeSolidImage(size: CGSize(width: 800, height: 400), color: .red)
        let data = try #require(AvatarImageCompressor.compressForUpload(landscape))

        let decoded = try #require(UIImage(data: data))
        // UIImage 像素尺寸；scale = 1.0 由 compressor 显式设置。
        #expect(decoded.size.width == 400)
        #expect(decoded.size.height == 400)

        // JPEG SOI 魔数 0xFFD8 + 0xFF（APP0/EXIF）
        #expect(data.count > 4)
        #expect(data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF)

        // 设计 §8 P7 验收点："头像文件 < 200 KB"。
        #expect(data.count < 200 * 1024)
    }

    @Test
    func portraitImageIsCenterCroppedToSquare() throws {
        let portrait = Self.makeSolidImage(size: CGSize(width: 600, height: 1200), color: .blue)
        let data = try #require(AvatarImageCompressor.compressForUpload(portrait))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 400)
        #expect(decoded.size.height == 400)
    }

    @Test
    func smallImageIsUpscaledToOutputSize() throws {
        // 200×200 输入 → 仍输出 400×400（与服务端 cover-fit 行为一致：放大也算 cover）
        let small = Self.makeSolidImage(size: CGSize(width: 200, height: 200), color: .green)
        let data = try #require(AvatarImageCompressor.compressForUpload(small))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 400)
        #expect(decoded.size.height == 400)
    }

    @Test
    func transparentImageIsFlattenedToWhiteBackground() throws {
        // 透明 PNG → 编码 JPEG 后中心像素应接近白色（不变式 9 + §6.2 白底处理）
        let transparent = Self.makeTransparentImage(size: CGSize(width: 400, height: 400))
        let data = try #require(AvatarImageCompressor.compressForUpload(transparent))

        let decoded = try #require(UIImage(data: data))
        let centerPixel = try #require(Self.samplePixel(image: decoded, x: 200, y: 200))
        // JPEG 编码会有 1-2 灰阶损失；放宽容差到 ≥ 240 即可视为白底
        #expect(centerPixel.r >= 240)
        #expect(centerPixel.g >= 240)
        #expect(centerPixel.b >= 240)
    }

    @Test
    func returnsNilForUnencodableImage() {
        // 0×0 image 显然没法 jpegData encode；compressor 不抛错，返回 nil 让上层选择失败路径
        let invalid = UIImage()
        let data = AvatarImageCompressor.compressForUpload(invalid)
        #expect(data == nil)
    }

    // MARK: - Helpers

    private static func makeSolidImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func makeTransparentImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            // 不绘制任何东西，保留全透明 alpha=0
        }
    }

    /// 读 image 单像素 RGB；测试用，效率不重要。
    private static func samplePixel(image: UIImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let cg = image.cgImage else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (pixel[0], pixel[1], pixel[2])
    }
}
