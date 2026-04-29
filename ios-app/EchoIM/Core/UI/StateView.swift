import SwiftUI

/// 标准化的空态 / 错态包装，仅用于列表页这种全屏占位场景。
struct StateView: View {
    enum Kind {
        case empty(title: LocalizedStringKey, systemImage: String, hint: LocalizedStringKey?)
        case error(title: LocalizedStringKey, message: String, systemImage: String, retry: (() -> Void)?)
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case let .empty(title, systemImage, hint):
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let hint {
                    Text(hint)
                }
            }

        case let .error(title, message, systemImage, retry):
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } actions: {
                if let retry {
                    Button("重试", action: retry)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

extension StateView {
    static func empty(
        title: LocalizedStringKey,
        systemImage: String,
        hint: LocalizedStringKey? = nil
    ) -> StateView {
        StateView(kind: .empty(title: title, systemImage: systemImage, hint: hint))
    }

    static func error(
        title: LocalizedStringKey = "加载失败",
        message: String,
        systemImage: String = "exclamationmark.triangle",
        retry: (() -> Void)? = nil
    ) -> StateView {
        StateView(kind: .error(title: title, message: message, systemImage: systemImage, retry: retry))
    }
}
