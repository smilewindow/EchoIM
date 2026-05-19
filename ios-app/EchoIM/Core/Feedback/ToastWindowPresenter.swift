import SwiftUI
import UIKit

@MainActor
final class ToastWindowPresenter {
    private var overlayWindow: PassThroughWindow?

    var overlayWindowForTesting: UIWindow? {
        overlayWindow
    }

    func show(_ toast: ToastMessage, in scene: UIWindowScene) {
        let window = overlayWindow ?? makeWindow(in: scene)
        if window.windowScene !== scene {
            window.isHidden = true
            overlayWindow = makeWindow(in: scene)
        }

        let activeWindow = overlayWindow ?? window
        activeWindow.rootViewController = makeHostingController(for: toast)
        activeWindow.isHidden = false
    }

    func hide() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }

    private func makeWindow(in scene: UIWindowScene) -> PassThroughWindow {
        let window = PassThroughWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level.alert + 1
        window.backgroundColor = .clear
        overlayWindow = window
        return window
    }

    private func makeHostingController(for toast: ToastMessage) -> UIHostingController<some View> {
        let controller = UIHostingController(
            rootView: ZStack {
                ToastOverlay(toast: toast)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.18), value: toast.id)
        )
        controller.view.backgroundColor = .clear
        return controller
    }
}

final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        // overlay 根视图覆盖全屏；只有真正命中子视图时才拦截，透明区域继续传给 app。
        if hitView === rootViewController?.view {
            return nil
        }

        return hitView
    }
}
