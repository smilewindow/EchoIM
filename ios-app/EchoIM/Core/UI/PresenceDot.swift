import SwiftUI

struct PresenceDot: View {
    var size: CGFloat = 10
    var borderWidth: CGFloat = 1.5

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        ZStack {
            if size >= 9 {
                Circle()
                    .fill(Color.echoOnline.opacity(isAnimating ? 0 : 0.4))
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(isAnimating ? 1.8 : 1.0)
            }
            Circle()
                .fill(Color.echoOnline)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: borderWidth)
                )
        }
        .onAppear {
            guard size >= 9, !reducedMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .accessibilityLabel(Text("在线"))
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
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.purple).frame(width: 32, height: 32)
            PresenceDot(size: 8).offset(x: 2, y: 2)  // 聊天导航栏尺寸：无波纹
        }
    }
    .padding()
}
