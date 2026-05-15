import Testing
@testable import EchoIM

@Suite("ChatScrollState")
struct ChatScrollStateTests {
    @Test func initialState_isNearBottom() {
        let state = ChatScrollState()
        #expect(state.isNearBottom)
        #expect(state.newMessageCount == 0)
    }

    @Test func offsetBelowThreshold_staysNearBottom() {
        var state = ChatScrollState(threshold: 60)
        let didUpdate = state.updateOffset(30)
        #expect(didUpdate)
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

    @Test func offsetWithinEpsilon_isIgnored() {
        var state = ChatScrollState(threshold: 60, offsetEpsilon: 0.5)

        let didUpdate = state.updateOffset(0.25)
        #expect(!didUpdate)
        #expect(state.isNearBottom)
    }

    @Test func offsetWithinEpsilon_crossingThreshold_updatesNearBottom() {
        var state = ChatScrollState(threshold: 60, offsetEpsilon: 0.5)

        state.updateOffset(60.1)
        let didUpdate = state.updateOffset(59.9)

        #expect(didUpdate)
        #expect(state.isNearBottom)
    }

    @Test func incomingMessage_whenNotNearBottom_increments() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 1)
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 2)
    }

    @Test func incomingMessage_whenNearBottom_doesNotIncrement() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(30)
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 0)
    }

    @Test func scrollBackToBottom_resetsCount() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessage()
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 2)
        state.updateOffset(30)
        #expect(state.isNearBottom)
        #expect(state.newMessageCount == 0)
    }

    @Test func reset_clearsCount() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessage()
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

    @Test func peerNewestMessage_awayFromBottom_incrementsCountWithoutScrolling() {
        var state = ChatScrollState()
        _ = state.handleNewestMessage(isFromCurrentUser: false)
        state.updateOffset(100)

        #expect(state.handleNewestMessage(isFromCurrentUser: false) == .none)
        #expect(state.newMessageCount == 1)
    }

    @Test func peerNewestMessage_negativeOffsetAwayFromBottom_incrementsCountWithoutScrolling() {
        var state = ChatScrollState()
        _ = state.handleNewestMessage(isFromCurrentUser: false)
        state.updateOffset(-100)

        #expect(state.handleNewestMessage(isFromCurrentUser: false) == .none)
        #expect(state.newMessageCount == 1)
    }
}
