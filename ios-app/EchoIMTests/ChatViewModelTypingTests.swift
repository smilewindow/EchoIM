import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite
struct ChatViewModelTypingTests {
    @Test
    func firstInputSendsTypingStart() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        #expect(recorder.calls == [TypingCall(conversationId: 42, isStart: true)])
    }

    @Test
    func consecutiveInputsDoNotResendStart() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        vm.handleTypingInput()
        vm.handleTypingInput()
        #expect(recorder.calls == [TypingCall(conversationId: 42, isStart: true)])
    }

    @Test
    func idleTimeoutSendsTypingStop() async throws {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 0.10)
        vm.handleTypingInput()
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s >> 0.10s
        #expect(recorder.calls == [
            TypingCall(conversationId: 42, isStart: true),
            TypingCall(conversationId: 42, isStart: false),
        ])
    }

    @Test
    func subsequentInputAfterIdleStopRestartsCycle() async throws {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 0.10)
        vm.handleTypingInput()
        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s，让 idle 定时器到期
        vm.handleTypingInput()
        #expect(recorder.calls == [
            TypingCall(conversationId: 42, isStart: true),
            TypingCall(conversationId: 42, isStart: false),
            TypingCall(conversationId: 42, isStart: true),
        ])
    }

    @Test
    func explicitStopTypingSendsStopImmediately() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        vm.stopTyping()
        #expect(recorder.calls == [
            TypingCall(conversationId: 42, isStart: true),
            TypingCall(conversationId: 42, isStart: false),
        ])
    }

    @Test
    func stopTypingWithoutActiveDoesNotSend() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: 42, recorder: recorder, idleDuration: 5.0)
        vm.stopTyping()
        #expect(recorder.calls.isEmpty)
    }

    @Test
    func handleTypingInputIgnoredWhenConversationIdNil() {
        let recorder = TypingRecorder()
        let vm = makeVM(conversationId: nil, recorder: recorder, idleDuration: 5.0)
        vm.handleTypingInput()
        #expect(recorder.calls.isEmpty)
    }

    // MARK: - Helpers

    struct TypingCall: Equatable {
        let conversationId: Int
        let isStart: Bool
    }

    @MainActor
    final class TypingRecorder {
        var calls: [TypingCall] = []
        func record(_ conversationId: Int, _ isStart: Bool) {
            calls.append(TypingCall(conversationId: conversationId, isStart: isStart))
        }
    }

    private func makeVM(
        conversationId: Int?,
        recorder: TypingRecorder,
        idleDuration: TimeInterval
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
            messageRepo: TypingNoopMessageRepository(),
            wsClient: nil,
            typingSender: { cid, isStart in recorder.record(cid, isStart) },
            idleTypingDuration: idleDuration,
            tokenProvider: { "tok" }
        )
    }
}

private struct TypingNoopMessageRepository: MessageRepository {
    func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] { [] }
    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func sendImage(recipientId: Int, mediaUrl: String, mediaWidth: Int, mediaHeight: Int, clientTempId: String, token: String) async throws -> Message {
        throw URLError(.badServerResponse)
    }
    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
}
