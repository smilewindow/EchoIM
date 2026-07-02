import CoreGraphics

struct ChatScrollState {
    enum NewMessageAction: Equatable {
        case scrollToBottom(animated: Bool)
        case none
    }

    private(set) var isNearBottom: Bool = true
    private(set) var newMessageCount: Int = 0

    let threshold: CGFloat

    private var hasHandledInitialNewestMessage = false

    init(threshold: CGFloat = 60) {
        self.threshold = threshold
    }

    /// 纯判断，不 mutate。滚动回调每帧触发，ChatView 用它前置过滤，
    /// 只有跨越阈值时才调 `updateOffset` 写 @State，避免整个 body 每帧重算。
    func isNearBottom(offset: CGFloat) -> Bool {
        // 翻转 ScrollView 下 offset 可能为负；这里统一成“离视觉底部的距离”。
        abs(offset) < threshold
    }

    @discardableResult
    mutating func updateOffset(_ offset: CGFloat) -> Bool {
        let nextIsNearBottom = isNearBottom(offset: offset)
        guard nextIsNearBottom != isNearBottom else { return false }

        isNearBottom = nextIsNearBottom
        if isNearBottom {
            newMessageCount = 0
        }
        return true
    }

    mutating func handleNewestMessage(isFromCurrentUser: Bool) -> NewMessageAction {
        guard hasHandledInitialNewestMessage else {
            hasHandledInitialNewestMessage = true
            return .scrollToBottom(animated: false)
        }

        if isFromCurrentUser || isNearBottom {
            newMessageCount = 0
            return .scrollToBottom(animated: true)
        }

        // 角标计数由 recordIncomingMessages 按批次驱动（VM 的 incomingMessageCount 差值），
        // tail 变化在批量到达时只触发一次，不能在这里 +1。
        return .none
    }

    mutating func recordIncomingMessages(_ count: Int) {
        guard !isNearBottom, count > 0 else { return }
        newMessageCount += count
    }

    mutating func reset() {
        newMessageCount = 0
    }
}
