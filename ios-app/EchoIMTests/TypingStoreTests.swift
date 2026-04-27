import Foundation
import Testing
@testable import EchoIM

@MainActor
@Suite
struct TypingStoreTests {
    @Test
    func startInsertsConversationId() {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        #expect(store.isTyping(7))
        #expect(store.typingConversationIds == [7])
    }

    @Test
    func explicitStopClearsImmediately() {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStop(conversationId: 7)
        #expect(!store.isTyping(7))
    }

    @Test
    func startIsIdempotentWithinWindow() async {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStart(conversationId: 7)
        #expect(store.typingConversationIds.count == 1)
    }

    @Test
    func safetyTimerAutoStops() async throws {
        let store = TypingStore(safetyDuration: 0.05)
        store.handleTypingStart(conversationId: 7)
        #expect(store.isTyping(7))

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!store.isTyping(7))
    }

    @Test
    func consecutiveStartsResetSafetyTimer() async throws {
        let store = TypingStore(safetyDuration: 0.10)
        store.handleTypingStart(conversationId: 7)
        try await Task.sleep(nanoseconds: 60_000_000)   // 0.06s
        store.handleTypingStart(conversationId: 7)
        try await Task.sleep(nanoseconds: 60_000_000)   // 又过 0.06s（共 0.12s，但新定时器才走了 0.06s）
        #expect(store.isTyping(7), "second start should have reset the safety timer")

        try await Task.sleep(nanoseconds: 100_000_000)  // 再等 0.10s 让新定时器到期
        #expect(!store.isTyping(7))
    }

    @Test
    func explicitStopCancelsSafetyTimer() async throws {
        let store = TypingStore(safetyDuration: 0.05)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStop(conversationId: 7)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.typingConversationIds.isEmpty)
    }

    @Test
    func independentConversationsAreTrackedSeparately() {
        let store = TypingStore(safetyDuration: 5.0)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStart(conversationId: 8)
        store.handleTypingStop(conversationId: 7)
        #expect(!store.isTyping(7))
        #expect(store.isTyping(8))
    }
}
