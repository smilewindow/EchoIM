import Testing
import UIKit
@testable import EchoIM

@MainActor
@Suite("LocalMessage")
struct LocalMessageTests {
    @Test
    func initializesLocalImageFromInitialData() throws {
        let data = try #require(makeJPEGData())

        let local = LocalMessage(
            localId: "tmp-1",
            message: makeImageMessage(clientTempId: "tmp-1"),
            sendState: .pending,
            localImageData: data
        )

        #expect(local.localImage != nil)
    }

    @Test
    func downsamplesLocalImageForBubblePreview() throws {
        let data = try #require(makeJPEGData(size: CGSize(width: 2000, height: 1000)))

        let local = LocalMessage(
            localId: "tmp-1",
            message: makeImageMessage(clientTempId: "tmp-1"),
            sendState: .pending,
            localImageData: data
        )

        let cg = try #require(local.localImage?.cgImage)
        #expect(max(cg.width, cg.height) <= ImageCompressor.previewMaxPixelSize)
    }

    @Test
    func updatesLocalImageWhenLocalImageDataChanges() throws {
        let initialData = try #require(makeJPEGData(color: .red))
        let previewData = try #require(makeJPEGData(color: .blue))

        var local = LocalMessage(
            localId: "tmp-1",
            message: makeImageMessage(clientTempId: "tmp-1"),
            sendState: .pending,
            localImageData: initialData
        )

        local.localImageData = previewData
        #expect(local.localImage != nil)

        local.localImageData = nil
        #expect(local.localImage == nil)
    }

    @Test
    func equalityIgnoresLocalImageCache() throws {
        let data = try #require(makeJPEGData())
        let message = makeImageMessage(clientTempId: "tmp-1")

        let lhs = LocalMessage(
            localId: "tmp-1",
            message: message,
            sendState: .pending,
            localImageData: data
        )
        let rhs = LocalMessage(
            localId: "tmp-1",
            message: message,
            sendState: .pending,
            localImageData: data
        )

        #expect(lhs == rhs)
    }

    private func makeImageMessage(clientTempId: String) -> Message {
        Message(
            id: -1,
            conversationId: 5,
            senderId: 3,
            body: nil,
            messageType: "image",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_745_800_000),
            clientTempId: clientTempId
        )
    }

    private func makeJPEGData(
        color: UIColor = .red,
        size: CGSize = CGSize(width: 8, height: 8)
    ) -> Data? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
