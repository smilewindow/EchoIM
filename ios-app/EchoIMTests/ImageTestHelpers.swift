import Foundation
@testable import EchoIM

@MainActor
final class MockUploadRepo: UploadRepository {
    var uploadResult: String = "/uploads/messages/3-0.jpg"
    var uploadError: Error?
    private(set) var uploadCalls = 0

    // P7：avatar 上传 stub。默认返回固定 URL；测试可按需覆盖。
    var uploadAvatarResult: String = "/uploads/avatars/3-0.jpg"
    var uploadAvatarError: Error?
    private(set) var uploadAvatarCalls = 0

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        uploadCalls += 1
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
    private var continuation: CheckedContinuation<String, Error>?
    private var avatarContinuation: CheckedContinuation<String, Error>?

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func uploadAvatar(data: Data, token: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.avatarContinuation = continuation
        }
    }

    func resume(with mediaURL: String) {
        continuation?.resume(returning: mediaURL)
        continuation = nil
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
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

@MainActor
final class MockMessageRepo: MessageRepository {
    struct SendImagePayload {
        let recipientId: Int
        let mediaUrl: String
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
        clientTempId: String,
        token: String
    ) async throws -> Message {
        sendImageCalls += 1
        sendImagePayloads.append(
            .init(recipientId: recipientId, mediaUrl: mediaUrl, clientTempId: clientTempId)
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
    metaStore: ConversationMetaStore? = nil
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
        tokenProvider: { "tok" }
    )
}
