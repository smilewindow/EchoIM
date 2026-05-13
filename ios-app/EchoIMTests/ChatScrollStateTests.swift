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
        state.updateOffset(30)
        #expect(state.isNearBottom)
    }

    @Test func offsetAboveThreshold_leavesBottom() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        #expect(!state.isNearBottom)
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
}
