import SwiftUI

struct ConversationsListView: View {
    @State private var vm: ConversationsListViewModel
    private let presenceStore: PresenceStore?

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
            .refreshable { await vm.refresh() }
            .task {
                vm.attachWSSubscription()
                await vm.load()
            }
            .onDisappear { vm.detachWSSubscription() }
            .toolbarBackground(Color.echoInteractive, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if case .unauthenticated = vm.phase {
            unauthenticatedState
        } else if vm.conversations.isEmpty {
            switch vm.phase {
            case .idle, .loading:
                // TabView 首帧不能给空内容；否则 SwiftUI 会把对应 tabItem 一起丢掉。
                ScrollView {
                    ConversationsListSkeleton()
                }
            case .loaded:
                emptyState
            case .error(let message):
                errorState(message)
            case .unauthenticated:
                unauthenticatedState
            }
        } else {
            list
        }
    }

    private var unauthenticatedState: some View {
        Text("登录状态已失效，请重新登录")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List(vm.conversations) { conversation in
            NavigationLink(value: ChatRoute.conversation(conversation)) {
                ConversationRow(conversation: conversation, presenceStore: presenceStore)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.echoBlue.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 70)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("conversationsList")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.echoBlue.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.echoBlue)
            }
            Text("暂无会话")
                .font(.headline)
                .foregroundStyle(Color.echoTextDeep)
            Text("从「联系人」里选一个好友\n开始聊天")
                .font(.subheadline)
                .foregroundStyle(Color.echoMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        StateView.error(message: message) {
            Task { await vm.load() }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let presenceStore: PresenceStore?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(profile: conversation.peer, size: 46)
                if presenceStore?.isOnline(conversation.peer.id) == true {
                    PresenceDot()
                        .offset(x: 2, y: 2)
                        .accessibilityIdentifier("conversationOnlineDot_\(conversation.peer.username)")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.peer.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.echoTextDeep)
                    .lineLimit(1)
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(Color.echoMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(Color.echoMuted)
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.echoDanger, in: Capsule())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var previewText: String {
        if let body = conversation.lastMessageBody, !body.isEmpty { return body }
        if conversation.lastMessageType == "image" { return String(localized: "[图片]") }
        return String(localized: "暂无消息")
    }

    private var timeString: String {
        guard let ts = conversation.lastMessageAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: ts, relativeTo: Date())
    }
}
