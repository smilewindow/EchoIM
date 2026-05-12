import CoreGraphics
import Testing
@testable import EchoIM

@Suite("Chat keyboard avoidance")
struct ChatKeyboardAvoidanceTests {
    @Test
    func returnsZeroWhenKeyboardDoesNotOverlapScreen() {
        let height = ChatKeyboardAvoidance.height(
            screenSize: CGSize(width: 390, height: 500),
            keyboardFrame: CGRect(x: 0, y: 520, width: 390, height: 260),
            bottomSafeAreaInset: 0
        )

        #expect(height == 0)
    }

    @Test
    func returnsCoveredHeightWhenKeyboardOverlapsBottom() {
        let height = ChatKeyboardAvoidance.height(
            screenSize: CGSize(width: 390, height: 812),
            keyboardFrame: CGRect(x: 0, y: 520, width: 390, height: 292),
            bottomSafeAreaInset: 0
        )

        #expect(height == 292)
    }

    @Test
    func subtractsBottomSafeAreaFromCoveredHeight() {
        let height = ChatKeyboardAvoidance.height(
            screenSize: CGSize(width: 390, height: 844),
            keyboardFrame: CGRect(x: 0, y: 508, width: 390, height: 336),
            bottomSafeAreaInset: 34
        )

        #expect(height == 302)
    }

    @Test
    func returnsZeroForFloatingKeyboard() {
        let height = ChatKeyboardAvoidance.height(
            screenSize: CGSize(width: 768, height: 1024),
            keyboardFrame: CGRect(x: 210, y: 650, width: 360, height: 260),
            bottomSafeAreaInset: 20
        )

        #expect(height == 0)
    }

    @Test
    func returnsZeroWhenKeyboardExactlyAtScreenBottom() {
        let height = ChatKeyboardAvoidance.height(
            screenSize: CGSize(width: 390, height: 812),
            keyboardFrame: CGRect(x: 0, y: 812, width: 390, height: 0),
            bottomSafeAreaInset: 0
        )

        #expect(height == 0)
    }

    @Test
    func returnsZeroWhenKeyboardHidden() {
        // keyboardHeight = 0 时哨兵为 CGFloat.greatestFiniteMagnitude，验证不产生负偏移。
        let height = ChatKeyboardAvoidance.height(
            screenSize: CGSize(width: 390, height: 812),
            keyboardFrame: CGRect(
                x: 0,
                y: CGFloat.greatestFiniteMagnitude,
                width: 390,
                height: 0
            ),
            bottomSafeAreaInset: 0
        )

        #expect(height == 0)
    }

    @Test
    func ignoresSubPixelHeightChanges() {
        #expect(!ChatKeyboardAvoidance.shouldUpdateHeight(from: 302, to: 302.4))
    }

    @Test
    func updatesMeaningfulHeightChanges() {
        #expect(ChatKeyboardAvoidance.shouldUpdateHeight(from: 302, to: 303))
    }
}
