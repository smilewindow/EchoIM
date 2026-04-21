import SwiftUI

struct MessageBubble: View {
    let message: LocalMessage
    let isSelf: Bool
    var onRetry: () -> Void = {}

    var body: some View {
        HStack {
            if isSelf {
                Spacer(minLength: 40)
            }

            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                bubble
                footer
            }

            if !isSelf {
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        Text(message.message.body ?? "")
            .font(.body)
            .foregroundStyle(isSelf ? .white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelf ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
            )
            .opacity(message.sendState == .pending ? 0.65 : 1.0)
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
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("发送失败")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("重试", action: onRetry)
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
}
