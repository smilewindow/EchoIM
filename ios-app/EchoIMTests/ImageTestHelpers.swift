import Foundation
@testable import EchoIM

@MainActor
final class MockUploadRepo: UploadRepository {
    var uploadResult: UploadedMessageImage = UploadedMessageImage(
        mediaUrl: "/uploads/messages/3-0.jpg",
        mediaWidth: 1600,
        mediaHeight: 1200
    )
    var uploadError: Error?
    var progressEvents: [Double] = []
    private(set) var uploadCalls = 0

    // P7：avatar 上传 stub。默认返回固定 URL；测试可按需覆盖。
    var uploadAvatarResult: String = "/uploads/avatars/3-0.jpg"
    var uploadAvatarError: Error?
    private(set) var uploadAvatarCalls = 0

    func uploadMessageImage(
        data: Data,
        token: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)?
    ) async throws -> UploadedMessageImage {
        uploadCalls += 1
        for progress in progressEvents {
            onProgress?(progress)
        }
        if let uploadError {
            throw uploadError
        }
        return uploadResult
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        uploadAvatarCalls += 1
        if let uploadAvatarError {
            throw uploadAvatarError
        }
        return uploadAvatarResult
    }
}

@MainActor
final class SuspendableUploadRepo: UploadRepository {
    private var continuation: CheckedContinuation<UploadedMessageImage, Error>?
    private var avatarContinuation: CheckedContinuation<String, Error>?
    private var onProgress: ((Double) -> Void)?
    private var uploadWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var uploadCalls = 0
    private(set) var uploadedMessageImageData: [Data] = []

    func uploadMessageImage(
        data: Data,
        token: String,
        onProgress: (@MainActor @Sendable (Double) -> Void)?
    ) async throws -> UploadedMessageImage {
        uploadCalls += 1
        uploadedMessageImageData.append(data)
        self.onProgress = onProgress
        let waiters = uploadWaiters
        uploadWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.avatarContinuation = continuation
        }
    }

    func resume(with mediaURL: String, width: Int = 1600, height: Int = 1200) {
        continuation?.resume(
            returning: UploadedMessageImage(mediaUrl: mediaURL, mediaWidth: width, mediaHeight: height)
        )
        continuation = nil
        onProgress = nil
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        onProgress = nil
    }

    func emitProgress(_ progress: Double) {
        onProgress?(progress)
    }

    func waitForUploadCall() async {
        if uploadCalls > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            uploadWaiters.append(continuation)
        }
    }

    func resumeAvatar(with avatarURL: String) {
        avatarContinuation?.resume(returning: avatarURL)
        avatarContinuation = nil
    }

    func resumeAvatar(throwing error: Error) {
        avatarContinuation?.resume(throwing: error)
        avatarContinuation = nil
    }
}

actor SuspendableImagePreparer {
    private var continuation: CheckedContinuation<PreparedMessageImage?, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestedData: [Data] = []

    func prepare(data: Data) async -> PreparedMessageImage? {
        requestedData.append(data)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let waiters = requestWaiters
            requestWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func resume(returning result: PreparedMessageImage?) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func callCount() -> Int {
        requestedData.count
    }

    func waitForRequest() async {
        if !requestedData.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func requestedDataValues() -> [Data] {
        requestedData
    }
}

@MainActor
final class MockMessageRepo: MessageRepository {
    struct SendImagePayload {
        let recipientId: Int
        let mediaUrl: String
        let mediaWidth: Int
        let mediaHeight: Int
        let clientTempId: String
    }

    var listResult: Result<[Message], Error> = .success([])
    var sendTextResult: Result<Message, Error> = .failure(NSError(domain: "unset", code: 0))
    var sendImageResult: Result<Message, Error> = .failure(NSError(domain: "unset", code: 0))
    var markReadResult: Result<Void, Error> = .success(())

    private(set) var sendImageCalls = 0
    private(set) var sendImagePayloads: [SendImagePayload] = []

    func list(
        conversationId: Int,
        cursor: MessageCursor?,
        limit: Int?,
        token: String
    ) async throws -> [Message] {
        try listResult.get()
    }

    func sendText(
        recipientId: Int,
        body: String,
        clientTempId: String,
        token: String
    ) async throws -> Message {
        try sendTextResult.get()
    }

    func sendImage(
        recipientId: Int,
        mediaUrl: String,
        mediaWidth: Int,
        mediaHeight: Int,
        clientTempId: String,
        token: String
    ) async throws -> Message {
        sendImageCalls += 1
        sendImagePayloads.append(
            .init(
                recipientId: recipientId,
                mediaUrl: mediaUrl,
                mediaWidth: mediaWidth,
                mediaHeight: mediaHeight,
                clientTempId: clientTempId
            )
        )
        return try sendImageResult.get()
    }

    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {
        try markReadResult.get()
    }
}

@MainActor
func makeImageVM(
    currentUserId: Int,
    peerId: Int,
    conversationId: Int?,
    upload: UploadRepository,
    messages: MessageRepository,
    messageStore: MessageStore? = nil,
    metaStore: ConversationMetaStore? = nil,
    imagePreparer: (@Sendable (Data) async -> PreparedMessageImage?)? = nil,
    uploadedImageCacheSeeder: (@MainActor (Data, URL) -> Void)? = nil
) -> ChatViewModel {
    let peer = UserProfile(id: peerId, username: "p", displayName: nil, avatarUrl: nil)
    let route: ChatRoute = conversationId.map { id in
        ChatRoute.conversation(
            Conversation(
                id: id,
                createdAt: Date(),
                peer: peer,
                lastMessageBody: nil,
                lastMessageType: nil,
                lastMessageSenderId: nil,
                lastMessageAt: nil,
                lastReadMessageId: nil,
                unreadCount: 0
            )
        )
    } ?? .peer(peer)

    return ChatViewModel(
        route: route,
        currentUserId: currentUserId,
        messageRepo: messages,
        wsClient: nil,
        conversationRepository: nil,
        messageStore: messageStore,
        metaStore: metaStore,
        uploadRepo: upload,
        imagePreparer: imagePreparer,
        uploadedImageCacheSeeder: uploadedImageCacheSeeder,
        tokenProvider: { "tok" }
    )
}
