import NukeUI
import SwiftUI

struct ImageMessageBubble: View {
    let message: LocalMessage
    let isSelf: Bool
    var onTap: () -> Void = {}
    var onRetry: () -> Void = {}

    var body: some View {
        HStack {
            if isSelf {
                Spacer(minLength: 40)
            }

            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                imageContent
                    .frame(maxWidth: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .center) {
                        if message.sendState == .pending {
                            ZStack {
                                Color.black.opacity(0.25)
                                ProgressView()
                                    .tint(.white)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .onTapGesture {
                        if case .pending = message.sendState {
                            return
                        }
                        onTap()
                    }

                footer
            }

            if !isSelf {
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        // 优先渲染本地压缩数据，避免确认后立刻切远端 URL 导致缩略图闪烁。
        if let data = message.localImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let url = remoteURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else if state.error != nil {
                    placeholder {
                        Image(systemName: "photo.badge.exclamationmark")
                    }
                } else {
                    placeholder {
                        ProgressView()
                    }
                }
            }
        } else {
            placeholder {
                Image(systemName: "photo")
            }
        }
    }

    private var remoteURL: URL? {
        Endpoints.absolute(message.message.mediaUrl)
    }

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // 服务端暂不返回宽高；用常见照片比例占位，远端图加载后再按真实比例重排。
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            content()
                .foregroundStyle(.secondary)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
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
