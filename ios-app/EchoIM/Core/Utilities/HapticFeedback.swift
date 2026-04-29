import UIKit

/// 用户主动操作成功后的轻量触觉反馈；测试可注入记录器或 NoOp，避免碰 UIKit 硬件行为。
@MainActor
protocol HapticFeedbackProvider: AnyObject {
    func lightImpact()
    func success()
    func warning()
}

final class UIKitHapticFeedback: HapticFeedbackProvider {
    func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

final class NoOpHapticFeedback: HapticFeedbackProvider {
    func lightImpact() {}
    func success() {}
    func warning() {}
}
