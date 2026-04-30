struct ChatInitialScrollPolicy {
    private var didFinishInitialLoad = false
    private var hasPendingInitialCatchUpScroll = false

    mutating func markInitialLoadFinished() -> Bool {
        guard !didFinishInitialLoad else { return false }
        didFinishInitialLoad = true
        let shouldCatchUpScroll = hasPendingInitialCatchUpScroll
        hasPendingInitialCatchUpScroll = false
        return shouldCatchUpScroll
    }

    mutating func consumeMessageChangeForScroll() -> Bool {
        guard didFinishInitialLoad else {
            // 首屏加载期间如果尾消息变了，等 load 完成后补一次无动画滚底。
            hasPendingInitialCatchUpScroll = true
            return false
        }
        return true
    }
}
