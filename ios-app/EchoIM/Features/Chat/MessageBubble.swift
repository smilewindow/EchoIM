import SwiftUI

struct MessageBubble: View {
    let message: LocalMessage
    let isSelf: Bool
    var isConsecutive: Bool = false
    var onRetry: () -> Void = {}
    var onOpenImage: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        if message.message.messageType == "image" {
            ImageMessageBubble(
                message: message,
                isSelf: isSelf,
                onTap: onOpenImage,
                onRetry: onRetry
            )
        } else {
            textBubble
        }
    }

    private var bubbleCornerRadii: (topLeading: CGFloat, topTrailing: CGFloat,
                                     bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        if isSelf {
            return isConsecutive
                ? (16, 16, 16, 16)
                : (16, 4, 16, 16)
        } else {
            return isConsecutive
                ? (16, 16, 16, 16)
                : (4, 16, 16, 16)
        }
    }

    private var textBubble: some View {
        HStack {
            if isSelf { Spacer(minLength: 40) }

            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                let r = bubbleCornerRadii
                Text(message.message.body ?? "")
                    .font(.body)
                    .foregroundStyle(isSelf ? .white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: r.topLeading,
                            bottomLeadingRadius: r.bottomLeading,
                            bottomTrailingRadius: r.bottomTrailing,
                            topTrailingRadius: r.topTrailing
                        )
                        .fill(isSelf
                              ? Color.echoInteractive
                              : Color(uiColor: .secondarySystemBackground))
                        .shadow(
                            color: isSelf ? .clear : Color.echoBlue.opacity(0.1),
                            radius: 3, x: 0, y: 1
                        )
                    )
                    .opacity(message.sendState == .pending ? 0.65 : 1.0)

                footer
            }
            .transition(messageTransition)
            .animation(.easeOut(duration: 0.2), value: message.localId)

            if !isSelf { Spacer(minLength: 40) }
        }
        .accessibilityIdentifier("chatBubble_text_\(message.localId)")
    }

    private var messageTransition: AnyTransition {
        if reducedMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(
                scale: 0.8,
                anchor: isSelf ? .bottomTrailing : .bottomLeading
            ).combined(with: .opacity),
            removal: .opacity
        )
    }

    @ViewBuilder
    private var footer: some View {
        switch message.sendState {
        case .confirmed:
            EmptyView()
        case .pending:
            Text("发送中...")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.echoBlue)
                Text("发送失败")
                    .font(.caption2)
                    .foregroundStyle(Color.echoBlue)
                Button("重试", action: onRetry)
                    .font(.caption2)
                    .foregroundStyle(Color.echoBlue)
                    .buttonStyle(.plain)
            }
        }
    }
}
