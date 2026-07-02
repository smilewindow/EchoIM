import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite("ChatViewModel - Image send")
struct ChatViewModelImageTests {
    @Test
    func uploadSuccessSeedsImageCacheWithUploadedData() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = UploadedMessageImage(
            mediaUrl: "/uploads/messages/3-0.jpg",
            mediaWidth: 640,
            mediaHeight: 360
        )
        let messages = MockMessageRepo()
        messages.sendImageResult = .success(
            Message(
                id: 301,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-0.jpg",
                mediaWidth: 640,
                mediaHeight: 360,
                createdAt: Date(),
                clientTempId: "ignored"
            )
        )

        var seeded: [(data: Data, url: URL)] = []
        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            uploadedImageCacheSeeder: { data, url in
                seeded.append((data, url))
            }
        )

        let uploadData = Data([0xFF, 0xD8, 0x10])
        await vm.sendCompressedImage(data: uploadData, width: 640, height: 360)

        #expect(seeded.count == 1)
        #expect(seeded.first?.data == uploadData)
        #expect(seeded.first?.url == Endpoints.absolute("/uploads/messages/3-0.jpg"))
    }

    @Test
    func uploadFailureDoesNotSeedImageCache() async throws {
        let upload = MockUploadRepo()
        upload.uploadError = APIError.invalidResponse
        let messages = MockMessageRepo()

        var seedCalls = 0
        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            uploadedImageCacheSeeder: { _, _ in
                seedCalls += 1
            }
        )

        await vm.sendCompressedImage(data: Data([0xFF, 0xD8, 0x10]), width: 640, height: 360)

        #expect(seedCalls == 0)
        #expect(vm.messages.first.map { isFailedState($0.sendState) } == true)
    }

    private func isFailedState(_ state: MessageSendState) -> Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    @Test
    func sendOriginalImageInsertsPreviewBeforePreparationCompletes() async throws {
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()
        let preparer = SuspendableImagePreparer()
        let originalData = Data([0x01, 0x02, 0x03])

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            imagePreparer: { data in await preparer.prepare(data: data) }
        )

        let task = Task {
            await vm.sendImage(originalData: originalData)
        }

        await preparer.waitForRequest()

        #expect(await preparer.callCount() == 1)
        #expect(await preparer.requestedDataValues() == [originalData])
        #expect(vm.messages.count == 1)
        guard let local = vm.messages.first else {
            Issue.record("expected optimistic image message before preparation completes")
            await preparer.resume(returning: nil)
            await task.value
            return
        }
        #expect(local.sendState == .pending)
        #expect(local.message.messageType == "image")
        #expect(local.message.mediaUrl == nil)
        #expect(local.message.mediaWidth == nil)
        #expect(local.message.mediaHeight == nil)
        #expect(local.localImageData == originalData)
        #expect(vm.imageSendStages[local.localId] == .preparing)
        #expect(upload.uploadCalls == 0)
        #expect(messages.sendImageCalls == 0)

        await preparer.resume(returning: nil)
        await task.value
    }

    @Test
    func sendOriginalImageUsesPreparedPreviewAndUploadData() async throws {
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()
        let preparer = SuspendableImagePreparer()
        let originalData = Data([0x01, 0x02, 0x03])
        let uploadData = Data([0xFF, 0xD8, 0x10])
        let previewData = Data([0xFF, 0xD8, 0x70])

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            imagePreparer: { data in await preparer.prepare(data: data) }
        )

        let task = Task {
            await vm.sendImage(originalData: originalData)
        }

        await preparer.waitForRequest()
        guard let localId = vm.messages.first?.localId else {
            Issue.record("expected optimistic image message before preparation completes")
            await preparer.resume(returning: nil)
            await task.value
            return
        }

        await preparer.resume(
            returning: PreparedMessageImage(
                upload: ImageCompressionResult(data: uploadData, width: 640, height: 360),
                previewData: previewData
            )
        )
        await upload.waitForUploadCall()

        let local = try #require(vm.messages.first(where: { $0.localId == localId }))
        #expect(local.sendState == .pending)
        #expect(local.localImageData == previewData)
        #expect(local.message.mediaWidth == 640)
        #expect(local.message.mediaHeight == 360)
        #expect(upload.uploadCalls == 1)
        #expect(upload.uploadedMessageImageData == [uploadData])
        #expect(messages.sendImageCalls == 0)

        messages.sendImageResult = .success(
            Message(
                id: 202,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                mediaWidth: 640,
                mediaHeight: 360,
                createdAt: Date(),
                clientTempId: localId
            )
        )
        upload.resume(with: "/uploads/messages/3-1745800000000.jpg", width: 640, height: 360)
        await task.value

        let confirmed = try #require(vm.messages.first)
        #expect(confirmed.sendState == .confirmed)
        #expect(confirmed.localImageData == nil)
        #expect(vm._pendingImageCountForTesting() == 0)
    }

    @Test
    func sendOriginalImageReplacesDisplayWithPreviewWhenPreviewFinishesWhilePending() async throws {
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()
        let preparer = SuspendableImagePreparer()
        let originalData = Data([0x01, 0x02, 0x03])
        let previewData = Data([0xFF, 0xD8, 0x70])
        let uploadData = Data([0xFF, 0xD8, 0x10])

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            imagePreparer: { data in await preparer.prepare(data: data) }
        )

        let task = Task {
            await vm.sendImage(originalData: originalData)
        }

        await preparer.waitForRequest()
        await preparer.resume(
            returning: PreparedMessageImage(
                upload: ImageCompressionResult(data: uploadData, width: 640, height: 360),
                previewData: previewData
            )
        )
        await upload.waitForUploadCall()

        let previewed = try #require(vm.messages.first)
        #expect(previewed.sendState == .pending)
        #expect(previewed.localImageData == previewData)

        upload.resume(throwing: APIError.network(URLError(.timedOut)))
        await task.value

        let failed = try #require(vm.messages.first)
        if case .failed = failed.sendState {
            // expected
        } else {
            Issue.record("expected failed image to keep preview display")
        }
        #expect(failed.localImageData == previewData)
        #expect(upload.uploadedMessageImageData == [uploadData])
    }

    @Test
    func sendOriginalImageKeepsOriginalDisplayWhenPreparationHasNoPreview() async throws {
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()
        let preparer = SuspendableImagePreparer()
        let originalData = Data([0x01, 0x02, 0x03])
        let uploadData = Data([0xFF, 0xD8, 0x10])

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            imagePreparer: { data in await preparer.prepare(data: data) }
        )

        let task = Task {
            await vm.sendImage(originalData: originalData)
        }

        await preparer.waitForRequest()
        let localId = try #require(vm.messages.first?.localId)
        await preparer.resume(
            returning: PreparedMessageImage(
                upload: ImageCompressionResult(data: uploadData, width: 640, height: 360),
                previewData: nil
            )
        )
        await upload.waitForUploadCall()

        let pending = try #require(vm.messages.first(where: { $0.localId == localId }))
        #expect(pending.localImageData == originalData)
        #expect(upload.uploadedMessageImageData == [uploadData])

        messages.sendImageResult = .success(
            Message(
                id: 203,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000002.jpg",
                mediaWidth: 640,
                mediaHeight: 360,
                createdAt: Date(),
                clientTempId: localId
            )
        )
        upload.resume(with: "/uploads/messages/3-1745800000002.jpg", width: 640, height: 360)
        await task.value

        let confirmed = try #require(vm.messages.first)
        #expect(confirmed.sendState == .confirmed)
        #expect(confirmed.localImageData == nil)
        #expect(confirmed.message.mediaUrl == "/uploads/messages/3-1745800000002.jpg")
    }

    @Test
    func sendOriginalImageDropsOriginalDataAfterCompressionSucceeds() async throws {
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()
        let preparer = SuspendableImagePreparer()
        let originalData = Data(repeating: 0x01, count: 12)
        let uploadData = Data([0xFF, 0xD8, 0x10])

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            imagePreparer: { data in await preparer.prepare(data: data) }
        )

        let task = Task {
            await vm.sendImage(originalData: originalData)
        }

        await preparer.waitForRequest()
        await preparer.resume(
            returning: PreparedMessageImage(
                upload: ImageCompressionResult(data: uploadData, width: 640, height: 360),
                previewData: nil
            )
        )
        await upload.waitForUploadCall()

        upload.resume(throwing: APIError.network(URLError(.timedOut)))
        await task.value

        let local = try #require(vm.messages.first)
        #expect(local.localImageData == originalData)
        #expect(vm._pendingImageOriginalDataCountForTesting() == 0)
        #expect(vm._pendingImageUploadDataCountForTesting() == 1)
    }

    @Test
    func sendOriginalImageMarksFailedWhenPreparationFails() async throws {
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()
        let preparer = SuspendableImagePreparer()
        let originalData = Data([0x01, 0x02, 0x03])

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages,
            imagePreparer: { data in await preparer.prepare(data: data) }
        )

        let task = Task {
            await vm.sendImage(originalData: originalData)
        }

        await preparer.waitForRequest()
        await preparer.resume(returning: nil)
        await task.value

        let local = try #require(vm.messages.first)
        if case .failed = local.sendState {
            // expected
        } else {
            Issue.record("expected .failed after compression failure")
        }
        #expect(local.localImageData == originalData)
        #expect(vm.imageSendStages[local.localId] == .notStarted)
        #expect(upload.uploadCalls == 0)
        #expect(messages.sendImageCalls == 0)
    }

    @Test
    func sendImageHappyPathInsertsPendingThenConfirms() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = UploadedMessageImage(
            mediaUrl: "/uploads/messages/3-1745800000000.jpg",
            mediaWidth: 1600,
            mediaHeight: 1200
        )

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
        #expect(local.localImageData == nil)

        #expect(vm.imageSendStages.isEmpty)
        #expect(vm._pendingImageCountForTesting() == 0)
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
        #expect(vm.imageSendStages[local.localId] == .uploading(progress: 0))

        upload.resume(with: "/uploads/messages/3-1745800000000.jpg")
        await task.value
    }

    @Test
    func sendImageCoalescesEquivalentUploadProgress() async throws {
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
        let localId = try #require(vm.messages.first?.localId)

        upload.emitProgress(0.254)
        #expect(vm.imageSendStages[localId] == .uploading(progress: 0.25))

        upload.emitProgress(0.2549)
        #expect(vm.imageSendStages[localId] == .uploading(progress: 0.25))

        upload.resume(throwing: APIError.network(URLError(.timedOut)))
        await task.value
    }

    @Test
    func sendImageUpdatesUploadProgressBeforeSendMessage() async throws {
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
        let localId = try #require(vm.messages.first?.localId)

        upload.emitProgress(0.25)
        #expect(vm.imageSendStages[localId] == .uploading(progress: 0.25))

        upload.emitProgress(0.6)
        #expect(vm.imageSendStages[localId] == .uploading(progress: 0.6))

        upload.emitProgress(1.2)
        #expect(vm.imageSendStages[localId] == .uploading(progress: 1))
        #expect(messages.sendImageCalls == 0)

        messages.sendImageResult = .success(
            Message(
                id: 201,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                createdAt: Date(),
                clientTempId: localId
            )
        )
        upload.resume(with: "/uploads/messages/3-1745800000000.jpg")
        await task.value

        #expect(messages.sendImageCalls == 1)
        #expect(vm.imageSendStages.isEmpty)
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
        upload.uploadResult = UploadedMessageImage(
            mediaUrl: "/uploads/messages/3-1745800000000.jpg",
            mediaWidth: 1600,
            mediaHeight: 1200
        )
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
        #expect(vm.imageSendStages[local.localId] == .uploaded(mediaURL: "/uploads/messages/3-1745800000000.jpg", mediaWidth: 1600, mediaHeight: 1200))
        #expect(upload.uploadCalls == 1)
        #expect(messages.sendImageCalls == 1)
    }

    @Test
    func retrySkipsUploadWhenStageIsUploaded() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = UploadedMessageImage(
            mediaUrl: "/uploads/messages/3-1745800000000.jpg",
            mediaWidth: 1600,
            mediaHeight: 1200
        )

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
        #expect(updated.localImageData == nil)
        #expect(vm._pendingImageCountForTesting() == 0)
    }

    @Test
    func retryUploadedStageDoesNotNeedLocalImageData() async throws {
        let upload = MockUploadRepo()
        let messages = MockMessageRepo()
        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )
        let tempId = "manual-uploaded"
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
            stage: .uploaded(
                mediaURL: "/uploads/messages/3-1745800000000.jpg",
                mediaWidth: 1600,
                mediaHeight: 1200
            ),
            localData: nil
        )
        messages.sendImageResult = .success(
            Message(
                id: 302,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                createdAt: Date(),
                clientTempId: tempId
            )
        )

        await vm.retry(localId: tempId)

        #expect(upload.uploadCalls == 0)
        #expect(messages.sendImageCalls == 1)
        #expect(messages.sendImagePayloads.first?.mediaUrl == "/uploads/messages/3-1745800000000.jpg")
        let updated = try #require(vm.messages.first)
        #expect(updated.sendState == .confirmed)
        #expect(updated.message.id == 302)
        #expect(updated.localImageData == nil)
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
        upload.uploadResult = UploadedMessageImage(
            mediaUrl: "/uploads/messages/3-1745800000001.jpg",
            mediaWidth: 1600,
            mediaHeight: 1200
        )
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
        #expect(updated.localImageData == nil)
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
