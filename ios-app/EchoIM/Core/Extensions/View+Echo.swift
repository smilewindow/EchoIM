import SwiftUI

extension View {
    /// 应用 EchoIM 品牌导航栏样式：青蓝背景、强制可见（覆盖 scroll-edge 透明）、白色内容配色。
    func echoNavigationBarStyle() -> some View {
        self
            .toolbarBackground(Color.echoInteractive, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
