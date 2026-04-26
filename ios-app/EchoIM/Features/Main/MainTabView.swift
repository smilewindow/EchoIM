import SwiftUI

struct MainTabView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var selection: MainTab = .chats

    var body: some View {
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
    }

    @ViewBuilder
    private var chatsTab: some View {
        if let session = container.session {
            ConversationsListView(
                repository: session.makeConversationRepository(),
                messageRepo: session.makeMessageRepository(),
                metaStore: session.conversationMetaStore(),
                messageStore: session.messageStore(),
                wsClient: session.wsClient,
                uploadRepo: session.makeUploadRepository(),
                currentUserId: container.currentUser?.id ?? 0,
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
                messageRepo: session.makeMessageRepository(),
                conversationRepo: session.makeConversationRepository(),
                messageStore: session.messageStore(),
                metaStore: session.conversationMetaStore(),
                wsClient: session.wsClient,
                uploadRepo: session.makeUploadRepository(),
                currentUserId: container.currentUser?.id ?? 0,
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
}
