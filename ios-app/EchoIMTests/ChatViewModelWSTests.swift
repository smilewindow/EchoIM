import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — WS")
struct ChatViewModelWSTests {
    final class FakeMessageRepo: MessageRepository {
        var listResult: Result<[Message], Error> = .success([])
        var sendDelay: TimeInterval = 0
        var sendMessageId = 555
        private(set) var listCalls: [(Int, MessageCursor?)] = []

        func list(
            conversationId: Int,
            cursor: MessageCursor?,
            limit: Int?,
            token: String
        ) async throws -> [Message] {
            listCalls.append((conversationId, cursor))
            return try listResult.get()
        }

        func sendText(
            recipientId: Int,
            body: String,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            if sendDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(sendDelay * 1_000_000_000))
            }
            return Message(
                id: sendMessageId,
                conversationId: 5,
                senderId: 3,
                body: body,
                messageType: "text",
                mediaUrl: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(sendMessageId)),
                clientTempId: clientTempId
            )
        }

        func sendImage(
            recipientId: Int,
            mediaUrl: String,
            clientTempId: String,
            token: String
        ) async throws -> Message {
            throw APIError.invalidResponse
        }

        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
    }

    private func msg(
        id: Int,
        convId: Int = 5,
        senderId: Int = 3,
        body: String = "hi",
        tempId: String? = nil
    ) -> Message {
        Message(
            id: id,
            conversationId: convId,
            senderId: senderId,
            body: body,
            messageType: "text",
            mediaUrl: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
            clientTempId: tempId
        )
    }

    private func makeConversation(id: Int = 5, peerId: Int = 9) -> Conversation {
        let json = """
        { "id": \(id), "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": \(peerId), "peer_username": "alice",
          "peer_display_name": null, "peer_avatar_url": null,
          "last_message_body": null, "last_message_type": null,
          "last_message_sender_id": null, "last_message_at": null,
          "last_read_message_id": null, "unread_count": 0 }
        """.data(using: .utf8)!
        return try! APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    @Test
    func incomingMessageFromPeerIsAppended() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        vm.handleWSEvent(.messageNew(msg(id: 100, senderId: 3, body: "hey")))

        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].message.body == "hey")
        #expect(vm.messages[0].sendState == .confirmed)
    }

    @Test
    func ownEchoMergesWithPendingByClientTempId() async {
        let repo = FakeMessageRepo()
        repo.sendDelay = 0.05
        repo.sendMessageId = 555
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        let sendTask = Task { await vm.sendText("hi") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let tempId = vm.messages[0].localId

        // WS echo 比 REST 响应先到：必须合并 pending，而不是追加第二条。
        vm.handleWSEvent(.messageNew(msg(id: 555, senderId: 3, body: "hi", tempId: tempId)))

        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].sendState == .confirmed)
        #expect(vm.messages[0].message.id == 555)

        await sendTask.value
        #expect(vm.messages.count == 1)
    }

    @Test
    func duplicateMessageIdIsIgnored() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )
        let message = msg(id: 300)

        vm.handleWSEvent(.messageNew(message))
        vm.handleWSEvent(.messageNew(message))

        #expect(vm.messages.count == 1)
    }

    @Test
    func messageForDifferentConversationIsIgnored() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation(id: 5)),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )

        vm.handleWSEvent(.messageNew(msg(id: 1, convId: 77, senderId: 3, body: "other chat")))

        #expect(vm.messages.isEmpty)
    }

    @Test
    func draftConversationActivatedByPeerMessage() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .peer(UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)),
            currentUserId: 3,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )
        #expect(vm.conversationId == nil)

        vm.handleWSEvent(.messageNew(msg(id: 42, convId: 88, senderId: 9, body: "hello")))

        #expect(vm.conversationId == 88)
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].message.body == "hello")
    }

    @Test
    func conversationUpdatedTracksLastReadMessageId() {
        let repo = FakeMessageRepo()
        let vm = ChatViewModel(
            route: .conversation(makeConversation()),
            currentUserId: 9,
            messageRepo: repo,
            wsClient: nil,
            messageStore: nil,
            metaStore: nil,
            tokenProvider: { "jwt" }
        )
        #expect(vm.lastReadMessageId == nil)

        vm.handleWSEvent(
            .conversationUpdated(
                ConversationUpdatedPayload(conversationId: 5, lastReadMessageId: 99)
            )
        )
        #expect(vm.lastReadMessageId == 99)

        vm.handleWSEvent(
            .conversationUpdated(
                ConversationUpdatedPayload(conversationId: 5, lastReadMessageId: 150)
            )
        )
        #expect(vm.lastReadMessageId == 150)

        vm.handleWSEvent(
            .conversationUpdated(
                ConversationUpdatedPayload(conversationId: 5, lastReadMessageId: 80)
            )
        )
        #expect(vm.lastReadMessageId == 150)
    }

    @Test
    func wsImageMessageFromPeerAppendsAsImageBubble() async throws {
        let upload = MockUploadRepo()
        let messages = MockMessageRepo()
        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )

        vm.handleWSEvent(
            .messageNew(
                Message(
                    id: 500,
                    conversationId: 5,
                    senderId: 9,
                    body: nil,
                    messageType: "image",
                    mediaUrl: "/uploads/messages/9-1745900000000.jpg",
                    createdAt: Date(),
                    clientTempId: nil
                )
            )
        )

        await Task.yield()
        await Task.yield()

        let last = try #require(vm.messages.last)
        #expect(last.message.messageType == "image")
        #expect(last.message.mediaUrl == "/uploads/messages/9-1745900000000.jpg")
        #expect(last.localImageData == nil, "对方的图片不带本地 Data，UI 走 Nuke 远程加载")
        #expect(last.sendState == .confirmed)
    }

    @Test
    func wsEchoFromSelfMergesIntoPendingImageBubblePreservingLocalData() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = "/uploads/messages/3-1.jpg"
        let messages = MockMessageRepo()
        messages.sendImageResult = .success(
            Message(
                id: 600,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1.jpg",
                createdAt: Date(),
                clientTempId: "tmp-x"
            )
        )

        let vm = makeImageVM(
            currentUserId: 3,
            peerId: 9,
            conversationId: 5,
            upload: upload,
            messages: messages
        )

        let imgBytes = Data([0xFF, 0xD8, 0xFF])
        await vm.sendCompressedImage(data: imgBytes, width: 10, height: 10)

        let echo = Message(
            id: 600,
            conversationId: 5,
            senderId: 3,
            body: nil,
            messageType: "image",
            mediaUrl: "/uploads/messages/3-1.jpg",
            createdAt: Date(),
            clientTempId: try #require(vm.messages.first?.localId)
        )
        vm.handleWSEvent(.messageNew(echo))
        await Task.yield()

        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].localImageData == imgBytes, "WS echo 不应擦掉 localImageData")
        #expect(vm.messages[0].sendState == .confirmed)
    }
}
