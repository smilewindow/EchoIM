import CoreGraphics

enum ChatKeyboardAvoidance {
    static func height(screenHeight: CGFloat, keyboardMinY: CGFloat) -> CGFloat {
        max(0, screenHeight - keyboardMinY)
    }
}
