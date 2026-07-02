import Testing
@testable import EchoIM

@Suite("ChatScrollState")
struct ChatScrollStateTests {
    @Test func initialState_isNearBottom() {
        let state = ChatScrollState()
        #expect(state.isNearBottom)
        #expect(state.newMessageCount == 0)
    }

    @Test func offsetBelowThreshold_staysNearBottom_withoutUpdate() {
        var state = ChatScrollState(threshold: 60)
        let didUpdate = state.updateOffset(30)
        #expect(!didUpdate)
        #expect(state.isNearBottom)
    }

    @Test func offsetAboveThreshold_leavesBottom() {
        var state = ChatScrollState(threshold: 60)
        let didUpdate = state.updateOffset(100)
        #expect(didUpdate)
        #expect(!state.isNearBottom)
    }

    @Test func negativeOffsetAboveThreshold_leavesBottom() {
        var state = ChatScrollState(threshold: 60)
        let didUpdate = state.updateOffset(-100)
        #expect(didUpdate)
        #expect(!state.isNearBottom)
    }

    @Test func offsetChangeOnSameSideOfThreshold_isIgnored() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)

        let didUpdate = state.updateOffset(200)
        #expect(!didUpdate)
        #expect(!state.isNearBottom)
    }

    @Test func smallOffsetChange_crossingThreshold_updatesNearBottom() {
        var state = ChatScrollState(threshold: 60)

        state.updateOffset(60.1)
        let didUpdate = state.updateOffset(59.9)

        #expect(didUpdate)
        #expect(state.isNearBottom)
    }

    @Test func isNearBottomOffset_isPureAndDoesNotMutate() {
        let state = ChatScrollState(threshold: 60)
        #expect(state.isNearBottom(offset: 30))
        #expect(state.isNearBottom(offset: -30))
        #expect(!state.isNearBottom(offset: 100))
        #expect(!state.isNearBottom(offset: -100))
        #expect(state.isNearBottom)
        #expect(state.newMessageCount == 0)
    }

    @Test func incomingMessages_whenNotNearBottom_accumulate() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessages(1)
        #expect(state.newMessageCount == 1)
        // 重连补拉等批量场景一次累加整批数量
        state.recordIncomingMessages(50)
        #expect(state.newMessageCount == 51)
    }

    @Test func incomingMessages_whenNearBottom_doNotIncrement() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(30)
        state.recordIncomingMessages(1)
        #expect(state.newMessageCount == 0)
    }

    @Test func incomingMessages_nonPositiveCount_isIgnored() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessages(0)
        state.recordIncomingMessages(-3)
        #expect(state.newMessageCount == 0)
    }

    @Test func scrollBackToBottom_resetsCount() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessages(2)
        #expect(state.newMessageCount == 2)
        state.updateOffset(30)
        #expect(state.isNearBottom)
        #expect(state.newMessageCount == 0)
    }

    @Test func reset_clearsCount() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessages(1)
        state.reset()
        #expect(state.newMessageCount == 0)
    }

    @Test func firstNewestMessage_scrollsWithoutAnimation() {
        var state = ChatScrollState()

        #expect(state.handleNewestMessage(isFromCurrentUser: false) == .scrollToBottom(animated: false))
    }

    @Test func ownNewestMessage_scrollsWithAnimationAfterInitialMessage() {
        var state = ChatScrollState()
        _ = state.handleNewestMessage(isFromCurrentUser: false)
        state.updateOffset(100)

        #expect(state.handleNewestMessage(isFromCurrentUser: true) == .scrollToBottom(animated: true))
        #expect(state.newMessageCount == 0)
    }

    @Test func peerNewestMessage_nearBottom_scrollsWithAnimationAfterInitialMessage() {
        var state = ChatScrollState()
        _ = state.handleNewestMessage(isFromCurrentUser: false)

        #expect(state.handleNewestMessage(isFromCurrentUser: false) == .scrollToBottom(animated: true))
        #expect(state.newMessageCount == 0)
    }

    @Test func peerNewestMessage_awayFromBottom_doesNotScrollAndLeavesCountToRecord() {
        var state = ChatScrollState()
        _ = state.handleNewestMessage(isFromCurrentUser: false)
        state.updateOffset(100)

        // 计数由 recordIncomingMessages 驱动，handleNewestMessage 只决定滚动动作
        #expect(state.handleNewestMessage(isFromCurrentUser: false) == .none)
        #expect(state.newMessageCount == 0)

        state.recordIncomingMessages(1)
        #expect(state.newMessageCount == 1)
    }

    @Test func peerNewestMessage_negativeOffsetAwayFromBottom_doesNotScroll() {
        var state = ChatScrollState()
        _ = state.handleNewestMessage(isFromCurrentUser: false)
        state.updateOffset(-100)

        #expect(state.handleNewestMessage(isFromCurrentUser: false) == .none)
    }
}
