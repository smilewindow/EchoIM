import ImageIO
import Testing
import UIKit
@testable import EchoIM

@MainActor
@Suite
struct ImageCompressorTests {
    @Test
    func preparesMessageImageUploadAndPreviewFromOneEntryPoint() async throws {
        let big = makeOpaqueImage(size: CGSize(width: 4000, height: 2000), color: .red)
        let data = try #require(big.pngData())

        let prepared = try #require(await ImageCompressor.prepareForMessageImage(data: data))
        let previewData = try #require(prepared.previewData)
        let preview = try #require(UIImage(data: previewData)?.cgImage)

        #expect(prepared.upload.width == 1600)
        #expect(prepared.upload.height == 800)
        #expect(prepared.upload.data.starts(with: [0xFF, 0xD8]))
        #expect(preview.width == 720)
        #expect(preview.height == 360)
        #expect(previewData.starts(with: [0xFF, 0xD8]))
    }

    @Test
    func messageImagePreparationReturnsNilForInvalidImageBytes() async throws {
        let result = await ImageCompressor.prepareForMessageImage(data: Data([0x00, 0x01]))

        #expect(result == nil)
    }

    @Test
    func decodeThumbnailCapsLongerEdgeAtMaxPixelSize() throws {
        let big = makeOpaqueImage(size: CGSize(width: 2000, height: 1000), color: .red)
        let data = try #require(big.jpegData(compressionQuality: 0.9))

        let thumbnail = try #require(ImageCompressor.decodeThumbnail(from: data, maxPixelSize: 720))
        let cg = try #require(thumbnail.cgImage)

        #expect(max(cg.width, cg.height) <= 720)
        // 降采样保持宽高比
        #expect(cg.width == cg.height * 2)
    }

    @Test
    func decodeThumbnailKeepsSmallImageDimensions() throws {
        let small = makeOpaqueImage(size: CGSize(width: 8, height: 8), color: .blue)
        let data = try #require(small.jpegData(compressionQuality: 0.9))

        let thumbnail = try #require(ImageCompressor.decodeThumbnail(from: data, maxPixelSize: 720))
        let cg = try #require(thumbnail.cgImage)

        #expect(cg.width == 8)
        #expect(cg.height == 8)
    }

    @Test
    func decodeThumbnailReturnsNilForInvalidImageBytes() {
        #expect(ImageCompressor.decodeThumbnail(from: Data([0x00, 0x01]), maxPixelSize: 720) == nil)
    }

    @Test
    func decodeThumbnailHandlesJPEGWithEmbeddedThumbnail() throws {
        let big = makeOpaqueImage(size: CGSize(width: 2000, height: 1000), color: .red)
        let data = try #require(makeJPEGWithEmbeddedThumbnail(big))

        let thumbnail = try #require(ImageCompressor.decodeThumbnail(from: data, maxPixelSize: 720))
        let cg = try #require(thumbnail.cgImage)

        #expect(max(cg.width, cg.height) <= 720)
    }

    @Test
    func decodeThumbnailGeneratesWhenNoEmbeddedThumbnail() throws {
        // renderer 直出的 JPEG 不含内嵌缩略图；IfAbsent 模式必须自动从全图生成。
        let big = makeOpaqueImage(size: CGSize(width: 2000, height: 1000), color: .red)
        let data = try #require(big.jpegData(compressionQuality: 0.9))

        let thumbnail = try #require(ImageCompressor.decodeThumbnail(from: data, maxPixelSize: 720))
        let cg = try #require(thumbnail.cgImage)

        #expect(max(cg.width, cg.height) <= 720)
    }

    @Test
    func transparentInputBecomesWhiteBackgroundJPEG() throws {
        let transparent = makeTransparentPNG(size: CGSize(width: 200, height: 200))
        let result = try #require(ImageCompressor.compressForUpload(transparent))

        #expect(result.width == 200)
        #expect(result.height == 200)

        // JPEG 没有 alpha；透明输入必须落到白底，避免客户端和服务端压缩结果不一致。
        let decoded = try #require(UIImage(data: result.data))
        let pixel = readFirstPixel(decoded)
        #expect(pixel.r > 250)
        #expect(pixel.g > 250)
        #expect(pixel.b > 250)
    }

    @Test
    func resizesLongerEdgeTo1600WhenLarger() throws {
        let big = makeOpaqueImage(size: CGSize(width: 4000, height: 2000), color: .red)
        let result = try #require(ImageCompressor.compressForUpload(big))

        #expect(result.width == 1600)
        #expect(result.height == 800)
    }

    @Test
    func keepsOriginalDimensionsWhenSmaller() throws {
        let small = makeOpaqueImage(size: CGSize(width: 600, height: 400), color: .blue)
        let result = try #require(ImageCompressor.compressForUpload(small))

        #expect(result.width == 600)
        #expect(result.height == 400)
    }

    @Test
    func outputIsJPEGUnderTenMB() throws {
        let big = makeOpaqueImage(size: CGSize(width: 4000, height: 4000), color: .green)
        let result = try #require(ImageCompressor.compressForUpload(big))

        #expect(result.data.count < 10 * 1024 * 1024)
        #expect(result.data.starts(with: [0xFF, 0xD8]))
    }

    private struct RGB {
        let r: UInt8
        let g: UInt8
        let b: UInt8
    }

    private func makeTransparentPNG(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            // 保留透明像素，用来验证 white-fill flatten。
        }
    }

    private func makeOpaqueImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeJPEGWithEmbeddedThumbnail(_ image: UIImage) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }

        let properties: [CFString: Any] = [
            kCGImageDestinationEmbedThumbnail: true,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func readFirstPixel(_ image: UIImage) -> RGB {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return RGB(r: 0, g: 0, b: 0)
        }

        return RGB(r: bytes[0], g: bytes[1], b: bytes[2])
    }
}
