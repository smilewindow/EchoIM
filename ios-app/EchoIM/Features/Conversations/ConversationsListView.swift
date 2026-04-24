import SwiftUI

struct ConversationsListView: View {
    @State private var vm: ConversationsListViewModel
    private let conversationRepo: ConversationRepository
    private let messageRepo: MessageRepository
    private let metaStore: ConversationMetaStore?
    private let messageStore: MessageStore?
    private let wsClient: WebSocketClient?
    private let currentUserId: Int
    private let tokenProvider: @MainActor () -> String?

    /// VM 由列表页自己持有，避免 MainTabView 因容器状态变化重算时重复创建。
    init(
        repository: ConversationRepository,
        messageRepo: MessageRepository,
        metaStore: ConversationMetaStore?,
        messageStore: MessageStore?,
        wsClient: WebSocketClient?,
        currentUserId: Int,
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
        self.conversationRepo = repository
        self.messageRepo = messageRepo
        self.metaStore = metaStore
        self.messageStore = messageStore
        self.wsClient = wsClient
        self.currentUserId = currentUserId
        self.tokenProvider = tokenProvider
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("聊天")
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
                .navigationDestination(for: ChatRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .idle, .loading:
            if vm.conversations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }

        case .loaded:
            if vm.conversations.isEmpty {
                emptyState
            } else {
                list
            }

        case .error(let message):
            if vm.conversations.isEmpty {
                errorState(message)
            } else {
                list
            }

        case .unauthenticated:
            Text("登录已过期，请重新登录")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var list: some View {
        List(vm.conversations) { conversation in
            NavigationLink(value: ChatRoute.conversation(conversation)) {
                ConversationRow(conversation: conversation)
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
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("暂无会话")
                .foregroundStyle(.secondary)
            Text("从“联系人”里选一个好友开始聊天")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("加载失败")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重试") {
                Task {
                    await vm.load()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func destination(for route: ChatRoute) -> some View {
        ChatView(
            route: route,
            currentUserId: currentUserId,
            messageRepo: messageRepo,
            messageStore: messageStore,
            metaStore: metaStore,
            wsClient: wsClient,
            conversationRepository: conversationRepo,
            tokenProvider: {
                tokenProvider()
            }
        )
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(profile: conversation.peer, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.peer.displayName ?? conversation.peer.username)
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
            return "[图片]"
        }

        return "暂无消息"
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
