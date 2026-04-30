import Testing
@testable import EchoIM

@MainActor
@Suite("Chat initial scroll policy")
struct ChatInitialScrollPolicyTests {
    @Test
    func defersMessageChangesUntilInitialLoadFinishes() {
        var policy = ChatInitialScrollPolicy()

        #expect(policy.consumeMessageChangeForScroll() == false)
        #expect(policy.markInitialLoadFinished() == true)
    }

    @Test
    func laterMessageChangesScrollImmediatelyAfterInitialLoad() {
        var policy = ChatInitialScrollPolicy()

        #expect(policy.markInitialLoadFinished() == false)
        #expect(policy.consumeMessageChangeForScroll() == true)
    }

    @Test
    func emptyInitialLoadMakesFirstNewMessageScrollImmediately() {
        var policy = ChatInitialScrollPolicy()

        #expect(policy.markInitialLoadFinished() == false)
        #expect(policy.consumeMessageChangeForScroll() == true)
    }

    @Test
    func repeatedLoadFinishCallsStayStable() {
        var policy = ChatInitialScrollPolicy()

        #expect(policy.markInitialLoadFinished() == false)
        #expect(policy.markInitialLoadFinished() == false)

        #expect(policy.consumeMessageChangeForScroll() == true)
    }

    @Test
    func resetPolicyClearsPendingCatchUpScroll() {
        var policy = ChatInitialScrollPolicy()
        #expect(policy.consumeMessageChangeForScroll() == false)

        policy = ChatInitialScrollPolicy()

        #expect(policy.markInitialLoadFinished() == false)
        #expect(policy.consumeMessageChangeForScroll() == true)
    }

    @Test
    func multipleMessageChangesBeforeInitialLoadOnlyNeedOneCatchUpScroll() {
        var policy = ChatInitialScrollPolicy()

        #expect(policy.consumeMessageChangeForScroll() == false)
        #expect(policy.consumeMessageChangeForScroll() == false)
        #expect(policy.markInitialLoadFinished() == true)
        #expect(policy.markInitialLoadFinished() == false)
    }
}
