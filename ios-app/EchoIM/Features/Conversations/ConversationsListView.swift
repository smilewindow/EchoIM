import SwiftUI

struct ConversationsListView: View {
    @State private var vm: ConversationsListViewModel

    // ChatView 由 MainTabView 统一组装；列表页只需要在线状态渲染行头像。
    private let presenceStore: PresenceStore?

    /// VM 由列表页自己持有，避免 MainTabView 因容器状态变化重算时重复创建。
    init(
        repository: ConversationRepository,
        metaStore: ConversationMetaStore?,
        wsClient: WebSocketClient?,
        currentUserId: Int,
        presenceStore: PresenceStore? = nil,
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        _vm = State(
            wrappedValue: ConversationsListViewModel(
                repository: repository,
                metaStore: metaStore,
                tokenProvider: tokenProvider,
                currentUserId: { currentUserId },
                wsClient: wsClient
            )
        )
        self.presenceStore = presenceStore
    }

    var body: some View {
        content
            .refreshable {
                await vm.refresh()
            }
            .task {
                vm.attachWSSubscription()
                await vm.load()
            }
            .onDisappear {
                vm.detachWSSubscription()
            }
    }

    @ViewBuilder
    private var content: some View {
        if case .unauthenticated = vm.phase {
            Text("登录已过期，请重新登录")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.conversations.isEmpty {
            switch vm.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                emptyState
            case .error(let message):
                errorState(message)
            case .unauthenticated:
                EmptyView()
            }
        } else {
            // list 始终在此分支，保持结构性身份，避免 phase 切换时重建列表触发 Nuke 重复请求。
            list
        }
    }

    private var list: some View {
        List(vm.conversations) { conversation in
            NavigationLink(value: ChatRoute.conversation(conversation)) {
                ConversationRow(conversation: conversation, presenceStore: presenceStore)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            )
        }
        .listStyle(.plain)
        .accessibilityIdentifier("conversationsList")
    }

    private var emptyState: some View {
        StateView.empty(
            title: "暂无会话",
            systemImage: "bubble.left.and.bubble.right",
            hint: "从「联系人」里选一个好友开始聊天"
        )
    }

    private func errorState(_ message: String) -> some View {
        StateView.error(message: message) {
            Task {
                await vm.load()
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let presenceStore: PresenceStore?

    init(conversation: Conversation, presenceStore: PresenceStore? = nil) {
        self.conversation = conversation
        self.presenceStore = presenceStore
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(profile: conversation.peer, size: 44)
                if presenceStore?.isOnline(conversation.peer.id) == true {
                    PresenceDot()
                        .offset(x: 2, y: 2)
                        .accessibilityIdentifier("conversationOnlineDot_\(conversation.peer.username)")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.peer.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var previewText: String {
        if let body = conversation.lastMessageBody, !body.isEmpty {
            return body
        }

        if conversation.lastMessageType == "image" {
            return String(localized: "[图片]")
        }

        return String(localized: "暂无消息")
    }

    private var timeString: String {
        guard let timestamp = conversation.lastMessageAt else {
            return ""
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
