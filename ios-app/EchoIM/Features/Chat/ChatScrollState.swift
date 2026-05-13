import CoreGraphics

struct ChatScrollState {
    private(set) var isNearBottom: Bool = true
    private(set) var newMessageCount: Int = 0

    let threshold: CGFloat

    init(threshold: CGFloat = 60) {
        self.threshold = threshold
    }

    mutating func updateOffset(_ offset: CGFloat) {
        let wasNearBottom = isNearBottom
        isNearBottom = offset < threshold
        if isNearBottom, !wasNearBottom {
            newMessageCount = 0
        }
    }

    mutating func recordIncomingMessage() {
        guard !isNearBottom else { return }
        newMessageCount += 1
    }

    mutating func reset() {
        newMessageCount = 0
    }
}
