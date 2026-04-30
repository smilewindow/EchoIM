struct ChatInitialScrollPolicy {
    private enum State {
        case waitingForInitialLoad
        case waitingForInitialScroll
        case didPinInitialMessages
    }

    private var state: State = .waitingForInitialLoad

    mutating func markInitialLoadFinished(hasMessages: Bool) {
        guard state == .waitingForInitialLoad else { return }
        state = hasMessages ? .waitingForInitialScroll : .didPinInitialMessages
    }

    mutating func shouldAnimateNextScroll() -> Bool {
        switch state {
        case .waitingForInitialLoad, .waitingForInitialScroll:
            state = .didPinInitialMessages
            return false
        case .didPinInitialMessages:
            return true
        }
    }
}
