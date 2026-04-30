import Testing
@testable import EchoIM

@MainActor
@Suite("Chat initial scroll policy")
struct ChatInitialScrollPolicyTests {
    @Test
    func initialMessagesPinWithoutAnimationAndLaterScrollsAnimate() {
        var policy = ChatInitialScrollPolicy()

        #expect(policy.shouldAnimateNextScroll() == false)
        #expect(policy.shouldAnimateNextScroll() == true)
        #expect(policy.shouldAnimateNextScroll() == true)
    }

    @Test
    func emptyInitialLoadMakesFirstNewMessageAnimate() {
        var policy = ChatInitialScrollPolicy()

        policy.markInitialLoadFinished(hasMessages: false)

        #expect(policy.shouldAnimateNextScroll() == true)
    }

    @Test
    func nonEmptyInitialLoadStillPinsFirstScrollWithoutAnimation() {
        var policy = ChatInitialScrollPolicy()

        policy.markInitialLoadFinished(hasMessages: true)

        #expect(policy.shouldAnimateNextScroll() == false)
        #expect(policy.shouldAnimateNextScroll() == true)
    }

    @Test
    func newPolicyStartsWithInitialPinAgain() {
        var policy = ChatInitialScrollPolicy()
        _ = policy.shouldAnimateNextScroll()

        policy = ChatInitialScrollPolicy()

        #expect(policy.shouldAnimateNextScroll() == false)
    }
}
