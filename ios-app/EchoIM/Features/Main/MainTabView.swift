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

    private var chatsTab: some View {
        ConversationsListView(
            repository: container.session!.makeConversationRepository(),
            messageRepo: container.session!.makeMessageRepository(),
            wsClient: container.session!.wsClient,
            currentUserId: container.currentUser?.id ?? 0,
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            }
        )
    }

    private var contactsTab: some View {
        ContactsView(
            friendRepo: container.makeFriendRepository(),
            requestRepo: container.makeFriendRequestRepository(),
            userRepo: container.makeUserRepository(),
            messageRepo: container.session!.makeMessageRepository(),
            conversationRepo: container.session!.makeConversationRepository(),
            wsClient: container.session!.wsClient,
            currentUserId: container.currentUser?.id ?? 0,
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            }
        )
    }

    private var meTab: some View {
        MeView(container: container, onLogout: onLogout)
    }
}
