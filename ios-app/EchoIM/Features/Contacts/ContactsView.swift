import SwiftUI

struct ContactsView: View {
    @State private var vm: ContactsViewModel
    private let userRepo: UserRepository
    private let messageRepo: MessageRepository
    private let conversationRepo: ConversationRepository
    private let messageStore: MessageStore?
    private let metaStore: ConversationMetaStore?
    private let wsClient: WebSocketClient?
    private let uploadRepo: UploadRepository
    private let currentUserId: Int
    private let tokenProvider: () -> String?

    // P6：presence / typing 透传到 FriendsListView 和 ChatView
    private let presenceStore: PresenceStore?
    private let typingStore: TypingStore?
    private let typingSender: @MainActor (Int, Bool) -> Void

    @State private var showRequests = false
    @State private var showSearch = false

    init(
        friendRepo: FriendRepository,
        requestRepo: FriendRequestRepository,
        userRepo: UserRepository,
        messageRepo: MessageRepository,
        conversationRepo: ConversationRepository,
        messageStore: MessageStore?,
        metaStore: ConversationMetaStore?,
        wsClient: WebSocketClient?,
        uploadRepo: UploadRepository,
        currentUserId: Int,
        presenceStore: PresenceStore? = nil,
        typingStore: TypingStore? = nil,
        typingSender: @escaping @MainActor (Int, Bool) -> Void = { _, _ in },
        tokenProvider: @escaping () -> String?
    ) {
        _vm = State(
            wrappedValue: ContactsViewModel(
                friendRepo: friendRepo,
                requestRepo: requestRepo,
                tokenProvider: tokenProvider
            )
        )
        self.userRepo = userRepo
        self.messageRepo = messageRepo
        self.conversationRepo = conversationRepo
        self.messageStore = messageStore
        self.metaStore = metaStore
        self.wsClient = wsClient
        self.uploadRepo = uploadRepo
        self.currentUserId = currentUserId
        self.presenceStore = presenceStore
        self.typingStore = typingStore
        self.typingSender = typingSender
        self.tokenProvider = tokenProvider
    }

    var body: some View {
        NavigationStack {
            FriendsListView(friends: vm.friends, presenceStore: presenceStore)
                .navigationTitle("联系人")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showRequests = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "envelope")

                                if vm.pendingIncomingCount > 0 {
                                    Text("\(vm.pendingIncomingCount)")
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
                            showSearch = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("openUserSearch")
                    }
                }
                .task {
                    await vm.refresh()
                }
                .refreshable {
                    await vm.refresh()
                }
                .navigationDestination(for: ChatRoute.self) { route in
                    ChatView(
                        route: route,
                        currentUserId: currentUserId,
                        messageRepo: messageRepo,
                        messageStore: messageStore,
                        metaStore: metaStore,
                        wsClient: wsClient,
                        conversationRepository: conversationRepo,
                        uploadRepo: uploadRepo,
                        presenceStore: presenceStore,
                        typingStore: typingStore,
                        typingSender: typingSender,
                        tokenProvider: {
                            tokenProvider()
                        }
                    )
                }
                .sheet(isPresented: $showRequests, onDismiss: refreshAfterSheet) {
                    FriendRequestsSheetView(vm: vm) {
                        showRequests = false
                    }
                }
                .sheet(isPresented: $showSearch, onDismiss: refreshAfterSheet) {
                    UserSearchSheetView(
                        vm: vm,
                        userRepo: userRepo,
                        tokenProvider: tokenProvider
                    ) {
                        showSearch = false
                    }
                }
        }
    }

    private func refreshAfterSheet() {
        Task {
            await vm.refresh()
        }
    }
}
