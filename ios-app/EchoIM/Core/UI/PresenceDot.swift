import SwiftUI

/// 好友 / 会话 / 聊天页头部用的"在线"圆点。
/// 颜色固定为绿色（系统语义 .green），边框白色保证在头像和深色背景上都可见。
/// 调用方负责决定显示与否（基于 PresenceStore），并放在合适的相对位置（一般是头像右下角 overlay）。
struct PresenceDot: View {
    var size: CGFloat = 10
    var borderWidth: CGFloat = 1.5

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color(uiColor: .systemBackground), lineWidth: borderWidth)
            )
            .accessibilityLabel("在线")
            .accessibilityHidden(false)
    }
}

#Preview {
    HStack(spacing: 16) {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.gray).frame(width: 40, height: 40)
            PresenceDot().offset(x: 2, y: 2)
        }
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.blue).frame(width: 56, height: 56)
            PresenceDot(size: 14).offset(x: 2, y: 2)
        }
    }
    .padding()
}
