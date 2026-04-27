import Foundation
import Observation

/// 设计 §8 P6。`@Observable` 会话级输入指示集合。
/// 每个 conversationId 维护独立的 5 秒兜底 Task，保证服务端 stop 丢失也能复位（不变式 6 / 7）。
@Observable
@MainActor
final class TypingStore {
    private(set) var typingConversationIds: Set<Int> = []

    private var safetyTimers: [Int: Task<Void, Never>] = [:]
    private let safetyDuration: TimeInterval

    init(safetyDuration: TimeInterval = 5.0) {
        self.safetyDuration = safetyDuration
    }

    /// 处理服务端转发的 typing.start。重置该会话的兜底定时器。
    func handleTypingStart(conversationId: Int) {
        typingConversationIds.insert(conversationId)
        safetyTimers[conversationId]?.cancel()

        let nanos = UInt64(safetyDuration * 1_000_000_000)
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self else { return }
            self.handleTypingStop(conversationId: conversationId)
        }
        safetyTimers[conversationId] = task
    }

    /// 处理服务端转发的 typing.stop（或兜底定时器自动调用）。同步取消该会话兜底定时器。
    func handleTypingStop(conversationId: Int) {
        typingConversationIds.remove(conversationId)
        safetyTimers.removeValue(forKey: conversationId)?.cancel()
    }

    func isTyping(_ conversationId: Int) -> Bool {
        typingConversationIds.contains(conversationId)
    }
}
