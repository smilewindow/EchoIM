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

    @Test
    func sendImageMarksFailedWhenUploadFails() async throws {
        let upload = MockUploadRepo()
        upload.uploadError = APIError.network(URLError(.notConnectedToInternet))
        let messages = MockMessageRepo()

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )

        await vm.sendCompressedImage(data: Data([0xFF]), width: 10, height: 10)

        #expect(vm.messages.count == 1)
        let local = try #require(vm.messages.first)
        if case .failed = local.sendState {
            // expected
        } else {
            Issue.record("expected .failed, got \(local.sendState)")
        }
        #expect(vm.imageSendStages[local.localId] == .notStarted)
        #expect(messages.sendImageCalls == 0)
    }

    @Test
    func sendImageMarksFailedWhenSendFailsButKeepsUploadedStage() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = "/uploads/messages/3-1745800000000.jpg"
        let messages = MockMessageRepo()
        messages.sendImageResult = .failure(APIError.network(URLError(.timedOut)))

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )

        await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)

        let local = try #require(vm.messages.first)
        if case .failed = local.sendState {
            // expected
        } else {
            Issue.record("expected .failed")
        }
        #expect(vm.imageSendStages[local.localId] == .uploaded(mediaURL: "/uploads/messages/3-1745800000000.jpg"))
        #expect(upload.uploadCalls == 1)
        #expect(messages.sendImageCalls == 1)
    }

    @Test
    func retrySkipsUploadWhenStageIsUploaded() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = "/uploads/messages/3-1745800000000.jpg"

        let messages = MockMessageRepo()
        messages.sendImageResult = .failure(APIError.network(URLError(.timedOut)))

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )
        await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)

        let localId = try #require(vm.messages.first?.localId)

        messages.sendImageResult = .success(
            Message(
                id: 300,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                createdAt: Date(),
                clientTempId: nil
            )
        )

        await vm.retry(localId: localId)

        #expect(upload.uploadCalls == 1, "retry 命中 .uploaded 阶段时不应重新上传")
        #expect(messages.sendImageCalls == 2)

        let updated = try #require(vm.messages.first)
        #expect(updated.sendState == .confirmed)
        #expect(updated.message.id == 300)
        #expect(vm.imageSendStages.isEmpty)
    }

    @Test
    func retryRestartsFromUploadWhenStageIsNotStarted() async throws {
        let upload = MockUploadRepo()
        upload.uploadError = APIError.network(URLError(.timedOut))

        let messages = MockMessageRepo()

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )
        await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)

        let localId = try #require(vm.messages.first?.localId)

        upload.uploadError = nil
        upload.uploadResult = "/uploads/messages/3-1745800000001.jpg"
        messages.sendImageResult = .success(
            Message(
                id: 301,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000001.jpg",
                createdAt: Date(),
                clientTempId: nil
            )
        )

        await vm.retry(localId: localId)

        #expect(upload.uploadCalls == 2, "上传失败后 retry 必须重新走上传")
        #expect(messages.sendImageCalls == 1)
        let updated = try #require(vm.messages.first)
        #expect(updated.sendState == .confirmed)
        #expect(updated.message.mediaUrl == "/uploads/messages/3-1745800000001.jpg")
    }

    @Test
    func retryNoOpsWhenLocalImageDataMissing() async throws {
        let upload = MockUploadRepo()
        let messages = MockMessageRepo()
        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )

        let tempId = "manual-tmp"
        vm._injectFailedImageBubbleForTesting(
            tempId: tempId,
            message: Message(
                id: -1,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: nil,
                createdAt: Date(),
                clientTempId: tempId
            ),
            stage: .notStarted,
            localData: nil
        )

        await vm.retry(localId: tempId)

        #expect(upload.uploadCalls == 0)
        #expect(messages.sendImageCalls == 0)
        let local = try #require(vm.messages.first)
        if case .failed = local.sendState {
            // unchanged
        } else {
            Issue.record("expected .failed unchanged")
        }
    }
}
