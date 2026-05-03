import SwiftUI

struct MainTabView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var path = NavigationPath()
    @State private var selection: MainTab = .chats
    @State private var showContactRequests = false
    @State private var showContactSearch = false
    @State private var pendingIncomingCount = 0

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $selection) {
                chatsTab
                    .tabItem {
                        Label("聊天", systemImage: MainTab.chats.systemImage)
                    }
                    .tag(MainTab.chats)

                contactsTab
                    .tabItem {
                        Label("联系人", systemImage: MainTab.contacts.systemImage)
                    }
                    .tag(MainTab.contacts)

                meTab
                    .tabItem {
                        Label("我", systemImage: MainTab.me.systemImage)
                    }
                    .tag(MainTab.me)
            }
            .accessibilityIdentifier("mainTabView")
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selection == .contacts, path.isEmpty {
                    contactsToolbar
                }
            }
            .navigationDestination(for: ChatRoute.self) { route in
                chatDestination(for: route)
            }
            .navigationDestination(for: UserProfile.self) { profile in
                UserDetailView(profile: profile, presenceStore: container.session?.presenceStore)
            }
        }
    }

    @ViewBuilder
    private var chatsTab: some View {
        if let session = container.session {
            ConversationsListView(
                repository: session.makeConversationRepository(),
                metaStore: session.conversationMetaStore(),
                wsClient: session.wsClient,
                currentUserId: container.currentUser?.id ?? 0,
                presenceStore: session.presenceStore,
                tokenProvider: { [tokenStore = container.tokenStore] in
                    (try? tokenStore.load())?.token
                }
            )
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var contactsTab: some View {
        if let session = container.session {
            ContactsView(
                friendRepo: container.makeFriendRepository(),
                requestRepo: container.makeFriendRequestRepository(),
                userRepo: container.makeUserRepository(),
                showRequests: $showContactRequests,
                showSearch: $showContactSearch,
                onPendingIncomingCountChange: { pendingIncomingCount = $0 },
                presenceStore: session.presenceStore,
                tokenProvider: { [tokenStore = container.tokenStore] in
                    (try? tokenStore.load())?.token
                }
            )
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var meTab: some View {
        MeView(container: container, onLogout: onLogout)
    }

    @ViewBuilder
    private func chatDestination(for route: ChatRoute) -> some View {
        if let session = container.session {
            ChatView(
                route: route,
                currentUserId: container.currentUser?.id ?? 0,
                messageRepo: session.makeMessageRepository(),
                messageStore: session.messageStore(),
                metaStore: session.conversationMetaStore(),
                wsClient: session.wsClient,
                conversationRepository: session.makeConversationRepository(),
                uploadRepo: session.makeUploadRepository(),
                presenceStore: session.presenceStore,
                typingStore: session.typingStore,
                typingSender: { [weak ws = session.wsClient] cid, isStart in
                    ws?.sendTyping(conversationId: cid, isStart: isStart)
                },
                tokenProvider: { [tokenStore = container.tokenStore] in
                    (try? tokenStore.load())?.token
                }
            )
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch selection {
        case .chats:
            "聊天"
        case .contacts:
            "联系人"
        case .me:
            "我"
        }
    }

    @ToolbarContentBuilder
    private var contactsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showContactRequests = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "envelope")

                    if pendingIncomingCount > 0 {
                        Text("\(pendingIncomingCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                            .offset(x: 10, y: -6)
                    }
                }
            }
            .accessibilityIdentifier("openFriendRequests")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showContactSearch = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("openUserSearch")
        }
    }
}
