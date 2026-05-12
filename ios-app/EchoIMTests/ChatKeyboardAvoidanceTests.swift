import CoreGraphics
import Testing
@testable import EchoIM

@Suite("Chat keyboard avoidance")
struct ChatKeyboardAvoidanceTests {
    @Test
    func returnsZeroWhenKeyboardDoesNotOverlapScreen() {
        let height = ChatKeyboardAvoidance.height(
            screenHeight: 500,
            keyboardMinY: 520
        )

        #expect(height == 0)
    }

    @Test
    func returnsCoveredHeightWhenKeyboardOverlapsBottom() {
        let height = ChatKeyboardAvoidance.height(
            screenHeight: 812,
            keyboardMinY: 520
        )

        #expect(height == 292)
    }

    @Test
    func returnsZeroWhenKeyboardExactlyAtScreenBottom() {
        let height = ChatKeyboardAvoidance.height(
            screenHeight: 812,
            keyboardMinY: 812
        )

        #expect(height == 0)
    }

    @Test
    func returnsZeroWhenKeyboardHidden() {
        // keyboardHeight = 0 时哨兵为 CGFloat.greatestFiniteMagnitude，验证不产生负偏移。
        let height = ChatKeyboardAvoidance.height(
            screenHeight: 812,
            keyboardMinY: .greatestFiniteMagnitude
        )

        #expect(height == 0)
    }
}
