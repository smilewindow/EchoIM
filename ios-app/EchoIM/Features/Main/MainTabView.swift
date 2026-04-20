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
            repository: container.makeConversationRepository(),
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            }
        )
    }

    private var contactsTab: some View {
        Text("Contacts placeholder")
            .accessibilityIdentifier("tabContactsPlaceholder")
    }

    private var meTab: some View {
        Text("Me placeholder")
            .accessibilityIdentifier("tabMePlaceholder")
    }
}
