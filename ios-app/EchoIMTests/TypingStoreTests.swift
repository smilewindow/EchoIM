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
        // safetyDuration 抬到 0.10，等待 0.50s，避免并行运行时 sleep 精度抖动
        let store = TypingStore(safetyDuration: 0.10)
        store.handleTypingStart(conversationId: 7)
        #expect(store.isTyping(7))

        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s >> 0.10s
        #expect(!store.isTyping(7))
    }

    @Test
    func consecutiveStartsResetSafetyTimer() async throws {
        let store = TypingStore(safetyDuration: 0.20)
        store.handleTypingStart(conversationId: 7)
        try await Task.sleep(nanoseconds: 100_000_000)   // 0.10s（< 0.20s 定时器）
        // 旧定时器还没到期就再来一次 start——必须 reset 成新的 0.20s
        store.handleTypingStart(conversationId: 7)
        try await Task.sleep(nanoseconds: 100_000_000)   // 又过 0.10s（共 0.20s，但新定时器才走了 0.10s）
        #expect(store.isTyping(7), "second start should have reset the safety timer")

        try await Task.sleep(nanoseconds: 300_000_000)   // 再等 0.30s 让新定时器到期
        #expect(!store.isTyping(7))
    }

    @Test
    func explicitStopCancelsSafetyTimer() async throws {
        let store = TypingStore(safetyDuration: 0.10)
        store.handleTypingStart(conversationId: 7)
        store.handleTypingStop(conversationId: 7)
        try await Task.sleep(nanoseconds: 300_000_000)   // 0.3s >> 0.10s
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
