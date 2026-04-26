import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("ChatViewModel - Image send")
struct ChatViewModelImageTests {
    @Test
    func sendImageHappyPathInsertsPendingThenConfirms() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = "/uploads/messages/3-1745800000000.jpg"

        let messages = MockMessageRepo()
        messages.sendImageResult = .success(
            Message(
                id: 200,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                createdAt: Date(),
                clientTempId: nil
            )
        )

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )

        let imgData = Data(repeating: 0xFF, count: 16)
        await vm.sendCompressedImage(data: imgData, width: 100, height: 100)

        #expect(upload.uploadCalls == 1)
        #expect(messages.sendImageCalls == 1)
        #expect(messages.sendImagePayloads.first?.mediaUrl == "/uploads/messages/3-1745800000000.jpg")

        #expect(vm.messages.count == 1)
        let local = try #require(vm.messages.first)
        #expect(local.sendState == .confirmed)
        #expect(local.message.id == 200)
        #expect(local.message.messageType == "image")
        #expect(local.localImageData == imgData)

        #expect(vm.imageSendStages.isEmpty)
    }

    @Test
    func sendImageInsertsOptimisticBubbleBeforeUpload() async throws {
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )

        let task = Task {
            await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)
        }

        await Task.yield()
        await Task.yield()

        #expect(vm.messages.count == 1)
        let local = try #require(vm.messages.first)
        #expect(local.sendState == .pending)
        #expect(local.message.messageType == "image")
        #expect(local.message.mediaUrl == nil)
        #expect(local.localImageData == Data([0xFF, 0xD8]))

        upload.resume(with: "/uploads/messages/3-1745800000000.jpg")
        await task.value
    }
}
