import Testing
import UIKit
@testable import EchoIM

@Suite
struct ImageCompressorTests {
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

    private func readFirstPixel(_ image: UIImage) -> RGB {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return RGB(r: 0, g: 0, b: 0)
        }

        return RGB(r: bytes[0], g: bytes[1], b: bytes[2])
    }
}
