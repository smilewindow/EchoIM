import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite
struct ChatViewModelPresenceTests {
    @Test
    func peerIsTypingReflectsTypingStoreState() {
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: 42, typingStore: typingStore)

        #expect(!vm.peerIsTyping)
        typingStore.handleTypingStart(conversationId: 42)
        #expect(vm.peerIsTyping)
        typingStore.handleTypingStop(conversationId: 42)
        #expect(!vm.peerIsTyping)
    }

    @Test
    func peerIsTypingFalseWhenConversationIdNil() {
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: nil, typingStore: typingStore)
        typingStore.handleTypingStart(conversationId: 99)
        #expect(!vm.peerIsTyping)
    }

    @Test
    func peerIsTypingIgnoresOtherConversations() {
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: 42, typingStore: typingStore)
        typingStore.handleTypingStart(conversationId: 999)
        #expect(!vm.peerIsTyping)
    }

    @Test
    func handleWSEventIgnoresTypingForOtherConversation() {
        // typing/presence 路由由 UserSession 负责（不变式 1 + 8）——
        // ChatViewModel 的 handleWSEvent 必须对这类事件保持 no-op；
        // 这里验证 VM 不重复写 typingStore（避免双计）。
        let typingStore = TypingStore(safetyDuration: 5.0)
        let vm = makeVM(conversationId: 42, typingStore: typingStore)
        vm.handleWSEvent(
            .typingStart(ConversationUserPayload(conversationId: 99, userId: 7))
        )
        #expect(!typingStore.isTyping(99), "ChatViewModel must not re-route typing events to typingStore — UserSession is the only writer")
    }

    // MARK: - Helpers

    private func makeVM(
        conversationId: Int?,
        typingStore: TypingStore
    ) -> ChatViewModel {
        let route: ChatRoute
        if let conversationId {
            route = .conversation(
                Conversation(
                    id: conversationId,
                    createdAt: Date(),
                    peer: UserProfile(id: 7, username: "alice", displayName: nil, avatarUrl: nil),
                    lastMessageBody: nil,
                    lastMessageType: nil,
                    lastMessageSenderId: nil,
                    lastMessageAt: nil,
                    lastReadMessageId: nil,
                    unreadCount: 0
                )
            )
        } else {
            route = .peer(
                UserProfile(id: 7, username: "alice", displayName: nil, avatarUrl: nil)
            )
        }
        return ChatViewModel(
            route: route,
            currentUserId: 100,
            messageRepo: PresenceNoopMessageRepository(),
            wsClient: nil,
            typingStore: typingStore,
            tokenProvider: { "tok" }
        )
    }
}

private struct PresenceNoopMessageRepository: MessageRepository {
    func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] { [] }
    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
}
