import Testing
@testable import EchoIM

@Suite("ScrollIndicatorMetrics")
struct ChatScrollIndicatorTests {
    @Test func contentFitsViewport_shouldNotShow() {
        let m = ScrollIndicatorMetrics(contentHeight: 500, viewportHeight: 800, offset: 0)
        #expect(!m.shouldShow)
    }

    @Test func contentExceedsViewport_shouldShow() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 0)
        #expect(m.shouldShow)
    }

    @Test func indicatorHeight_proportionalToViewport() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 0)
        #expect(m.indicatorHeight == 320)
    }

    @Test func indicatorHeight_respectsMinimum() {
        let m = ScrollIndicatorMetrics(contentHeight: 50000, viewportHeight: 800, offset: 0)
        #expect(m.indicatorHeight == 30)
    }

    @Test func offsetZero_indicatorAtBottom() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 0)
        #expect(m.indicatorTop == 480)
    }

    @Test func offsetMax_indicatorAtTop() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 1200)
        #expect(m.indicatorTop == 0)
    }

    @Test func offsetHalf_indicatorAtMiddle() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 600)
        #expect(m.indicatorTop == 240)
    }

    @Test func offsetClamped_neverNegative() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: -50)
        #expect(m.indicatorTop >= 0)
        #expect(m.indicatorTop <= 800)
    }

    @Test func offsetClamped_neverExceedsTrack() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 9999)
        #expect(m.indicatorTop == 0)
    }
}
