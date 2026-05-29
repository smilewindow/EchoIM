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

    private func makeJPEGData(color: UIColor = .red) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
