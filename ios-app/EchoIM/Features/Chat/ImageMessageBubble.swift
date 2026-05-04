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
                    .modifier(AspectRatioLockIfKnown(ratio: serverAspectRatio))
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
        .accessibilityIdentifier("chatBubble_image_\(message.localId)")
    }

    @ViewBuilder
    private var imageContent: some View {
        // 优先渲染本地压缩数据，避免确认后立刻切远端 URL 导致缩略图闪烁。
        if let data = message.localImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .modifier(ScaleToFitIfRatioUnknown(ratio: serverAspectRatio))
        } else if let url = remoteURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .modifier(ScaleToFitIfRatioUnknown(ratio: serverAspectRatio))
                } else if state.error != nil {
                    errorPlaceholder
                } else {
                    placeholder {
                        ProgressView()
                            .tint(.secondary)
                    }
                }
            }
        } else {
            placeholder {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var remoteURL: URL? {
        Endpoints.absolute(message.message.mediaUrl)
    }

    private var errorPlaceholder: some View {
        placeholder {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("图片加载失败")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 服务端发图时记录的像素宽高比；老消息没有这两列时返回 nil，由调用方退回原 scaledToFit 行为。
    private var serverAspectRatio: CGFloat? {
        if let width = message.message.mediaWidth, let height = message.message.mediaHeight,
           width > 0, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return nil
    }

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // 已知真实比例时，占位骨架也按最终比例铺开；未知时再回退到 4:3。
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(serverAspectRatio ?? (4.0 / 3.0), contentMode: .fit)
    }

    /// 已知比例时锁定外层尺寸，让 ScrollView 在图片解码前就占用最终高度，消除 reflow。
    /// 比例缺失（老消息）时不施加，外层尺寸由内层 scaledToFit 后的图像决定。
    private struct AspectRatioLockIfKnown: ViewModifier {
        let ratio: CGFloat?

        func body(content: Content) -> some View {
            if let ratio {
                content.aspectRatio(ratio, contentMode: .fit)
            } else {
                content
            }
        }
    }

    /// 老消息没尺寸时仍按 scaledToFit，避免被 .resizable() 拉伸；新消息由 AspectRatioLockIfKnown 控制。
    private struct ScaleToFitIfRatioUnknown: ViewModifier {
        let ratio: CGFloat?

        func body(content: Content) -> some View {
            if ratio == nil {
                content.scaledToFit()
            } else {
                content
            }
        }
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
