import SwiftUI
import UIKit

struct WindowSceneReader: UIViewRepresentable {
    let onSceneChange: @MainActor (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> WindowSceneReaderView {
        let view = WindowSceneReaderView()
        view.onSceneChange = onSceneChange
        return view
    }

    func updateUIView(_ uiView: WindowSceneReaderView, context: Context) {
        uiView.onSceneChange = onSceneChange
        uiView.reportScene()
    }
}

@MainActor
final class WindowSceneReaderView: UIView {
    var onSceneChange: (@MainActor (UIWindowScene?) -> Void)?
    private weak var lastReportedScene: UIWindowScene?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportScene()
    }

    func reportScene() {
        let scene = window?.windowScene
        guard scene !== lastReportedScene else {
            return
        }

        lastReportedScene = scene
        Task { @MainActor [weak self, weak scene] in
            self?.onSceneChange?(scene)
        }
    }
}
