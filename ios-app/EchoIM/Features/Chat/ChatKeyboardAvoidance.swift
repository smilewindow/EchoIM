import CoreGraphics

enum ChatKeyboardAvoidance {
    private static let heightChangeThreshold: CGFloat = 0.5

    static func height(
        screenSize: CGSize,
        keyboardFrame: CGRect,
        bottomSafeAreaInset: CGFloat
    ) -> CGFloat {
        // iPad 浮动键盘不占据底部输入区；按宽度判断可避免误算成整屏避让。
        guard keyboardFrame.width >= screenSize.width else { return 0 }

        return max(0, screenSize.height - bottomSafeAreaInset - keyboardFrame.minY)
    }

    static func shouldUpdateHeight(from currentHeight: CGFloat, to nextHeight: CGFloat) -> Bool {
        abs(currentHeight - nextHeight) > heightChangeThreshold
    }
}
