import Foundation
import Testing
@testable import EchoIM

@MainActor
final class RecordingHaptics: HapticFeedbackProvider {
    private(set) var lightCount = 0
    private(set) var successCount = 0
    private(set) var warningCount = 0

    func lightImpact() {
        lightCount += 1
    }

    func success() {
        successCount += 1
    }

    func warning() {
        warningCount += 1
    }
}

@MainActor
@Suite("HapticFeedback 注入点")
struct HapticFeedbackInjectionTests {
    final class MessageRepo: MessageRepository {
        var textResult: Result<Message, Error> = .failure(APIError.invalidResponse)
        var imageResult: Result<Message, Error> = .failure(APIError.invalidResponse)

        func list(
            conversationId: Int,
            cursor: MessageCursor?,
            limit: Int?,
            token: String
        ) async throws -> [Message] {
            []
        }

        func sendText(
            recipientId: Int,
            body: String,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            try textResult.get()
        }

        func sendImage(
            recipientId: Int,
            mediaUrl: String,
            mediaWidth: Int,
            mediaHeight: Int,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            try imageResult.get()
        }

        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
    }

    final class UploadRepo: UploadRepository {
        func uploadMessageImage(data: Data, token: String) async throws -> UploadedMessageImage {
            UploadedMessageImage(mediaUrl: "/uploads/messages/test.jpg", mediaWidth: 100, mediaHeight: 100)
        }

        func uploadAvatar(data: Data, token: String) async throws -> String {
            "/uploads/avatars/test.jpg"
        }
    }

    final class FriendRepo: FriendRepository {
        func list(token: String) async throws -> [Friend] {
            []
        }
    }

    final class RequestRepo: FriendRequestRepository {
        var respondResult: Result<FriendRequest, Error> = .failure(APIError.invalidResponse)

        func listIncoming(token: String) async throws -> [FriendRequest] {
            []
        }

        func listSent(token: String) async throws -> [FriendRequest] {
            []
        }

        func listHistory(token: String) async throws -> [FriendRequest] {
            []
        }

        func send(recipientId: Int, token: String) async throws -> FriendRequest {
            throw APIError.invalidResponse
        }

        func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest {
            try respondResult.get()
        }
    }

    private func makePeer() -> UserProfile {
        UserProfile(id: 9, username: "peer", displayName: nil, avatarUrl: nil)
    }

    private func makeMessage(
        id: Int,
        body: String?,
        messageType: String,
        mediaUrl: String?,
        tempId: String
    ) -> Message {
        Message(
            id: id,
            conversationId: 1,
            senderId: 0,
            body: body,
            messageType: messageType,
            mediaUrl: mediaUrl,
            createdAt: Date(),
            clientTempId: tempId
        )
    }

    private func makeRequest(status: FriendRequestStatus) -> FriendRequest {
        FriendRequest(
            id: 1,
            senderId: 1,
            recipientId: 2,
            status: status,
            createdAt: Date(),
            updatedAt: Date(),
            direction: nil,
            username: nil,
            displayName: nil,
            avatarUrl: nil
        )
    }

    @Test
    func sendTextSuccessRestDoesNotTriggerHaptic() async {
        let repo = MessageRepo()
        repo.textResult = .success(
            makeMessage(id: 100, body: "hi", messageType: "text", mediaUrl: nil, tempId: "pending")
        )
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "tok" },
            haptics: haptics
        )

        await vm.sendText("hi")

        // REST 201 不再触发任何 haptic，WS echo 才触发
        #expect(haptics.lightCount == 0)
        #expect(haptics.successCount == 0)
        #expect(haptics.warningCount == 0)
    }

    @Test
    func wsEchoOfOwnMessageTriggersSuccess() async {
        let repo = MessageRepo()
        let message = makeMessage(id: 100, body: "hi", messageType: "text", mediaUrl: nil, tempId: "temp-1")
        repo.textResult = .success(message)
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: repo,
            wsClient: nil,
            tokenProvider: { "tok" },
            haptics: haptics
        )

        let echoMsg = Message(
            id: 100, conversationId: 1, senderId: 0, body: "hi",
            messageType: "text", mediaUrl: nil, createdAt: Date(), clientTempId: "temp-1"
        )

        await vm.sendText("hi")          // REST 路径，不触发
        vm.handleWSEvent(.messageNew(echoMsg))  // WS echo 路径，触发 success()

        #expect(haptics.successCount == 1)
        #expect(haptics.lightCount == 0)
    }

    @Test
    func sendTextFailureTriggersWarning() async {
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: MessageRepo(),  // textResult defaults to .failure
            wsClient: nil,
            tokenProvider: { "tok" },
            haptics: haptics
        )

        await vm.sendText("hi")

        #expect(haptics.warningCount == 1)
        #expect(haptics.successCount == 0)
        #expect(haptics.lightCount == 0)
    }

    @Test
    func sendImageSuccessRestDoesNotTriggerHaptic() async {
        let repo = MessageRepo()
        repo.imageResult = .success(
            makeMessage(
                id: 200,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/test.jpg",
                tempId: "pending"
            )
        )
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: repo,
            wsClient: nil,
            uploadRepo: UploadRepo(),
            tokenProvider: { "tok" },
            haptics: haptics
        )

        await vm.sendCompressedImage(data: Data([0xFF, 0xD8, 0xFF]), width: 100, height: 100)

        #expect(haptics.lightCount == 0)
        #expect(haptics.successCount == 0)
        #expect(haptics.warningCount == 0)
    }

    @Test
    func wsEchoOfOwnImageMessageTriggersSuccess() async {
        let repo = MessageRepo()
        let echoMsg = Message(
            id: 200, conversationId: 1, senderId: 0,
            body: nil, messageType: "image",
            mediaUrl: "/uploads/messages/test.jpg",
            createdAt: Date(), clientTempId: "img-temp-1"
        )
        repo.imageResult = .success(echoMsg)
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: repo,
            wsClient: nil,
            uploadRepo: UploadRepo(),
            tokenProvider: { "tok" },
            haptics: haptics
        )

        await vm.sendCompressedImage(data: Data([0xFF, 0xD8, 0xFF]), width: 100, height: 100)
        vm.handleWSEvent(.messageNew(echoMsg))  // WS echo 路径，触发 success()

        #expect(haptics.successCount == 1)
        #expect(haptics.lightCount == 0)
    }

    @Test
    func respondAcceptTriggersSuccess() async {
        let requestRepo = RequestRepo()
        requestRepo.respondResult = .success(makeRequest(status: .accepted))
        let haptics = RecordingHaptics()
        let vm = ContactsViewModel(
            friendRepo: FriendRepo(),
            requestRepo: requestRepo,
            tokenProvider: { "tok" },
            haptics: haptics
        )

        await vm.respond(requestId: 1, accept: true)

        #expect(haptics.successCount == 1)
        #expect(haptics.warningCount == 0)
    }

    @Test
    func respondDeclineTriggersWarning() async {
        let requestRepo = RequestRepo()
        requestRepo.respondResult = .success(makeRequest(status: .declined))
        let haptics = RecordingHaptics()
        let vm = ContactsViewModel(
            friendRepo: FriendRepo(),
            requestRepo: requestRepo,
            tokenProvider: { "tok" },
            haptics: haptics
        )

        await vm.respond(requestId: 1, accept: false)

        #expect(haptics.warningCount == 1)
        #expect(haptics.successCount == 0)
    }
}
