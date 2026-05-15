import CoreGraphics

struct ChatScrollState {
    enum NewMessageAction: Equatable {
        case scrollToBottom(animated: Bool)
        case none
    }

    private(set) var isNearBottom: Bool = true
    private(set) var newMessageCount: Int = 0

    let threshold: CGFloat
    let offsetEpsilon: CGFloat

    private var lastDistanceFromBottom: CGFloat = 0
    private var hasHandledInitialNewestMessage = false

    init(threshold: CGFloat = 60, offsetEpsilon: CGFloat = 0.5) {
        self.threshold = threshold
        self.offsetEpsilon = offsetEpsilon
    }

    @discardableResult
    mutating func updateOffset(_ offset: CGFloat) -> Bool {
        // 翻转 ScrollView 下 offset 可能为负；这里统一成“离视觉底部的距离”。
        let distanceFromBottom = abs(offset)
        let nextIsNearBottom = distanceFromBottom < threshold
        guard abs(distanceFromBottom - lastDistanceFromBottom) >= offsetEpsilon
                || nextIsNearBottom != isNearBottom else {
            return false
        }

        let wasNearBottom = isNearBottom
        lastDistanceFromBottom = distanceFromBottom
        isNearBottom = nextIsNearBottom
        if isNearBottom, !wasNearBottom {
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

        recordIncomingMessage()
        return .none
    }

    mutating func recordIncomingMessage() {
        guard !isNearBottom else { return }
        newMessageCount += 1
    }

    mutating func reset() {
        newMessageCount = 0
    }
}
