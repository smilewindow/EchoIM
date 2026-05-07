import SwiftUI

struct ContactsView: View {
    @State private var vm: ContactsViewModel
    private let userRepo: UserRepository
    private let tokenProvider: () -> String?
    private let onPendingIncomingCountChange: (Int) -> Void

    // ChatView 由 MainTabView 统一组装；联系人页只需要在线状态渲染好友列表。
    private let presenceStore: PresenceStore?

    @Binding private var showRequests: Bool
    @Binding private var showSearch: Bool

    init(
        friendRepo: FriendRepository,
        requestRepo: FriendRequestRepository,
        userRepo: UserRepository,
        showRequests: Binding<Bool>,
        showSearch: Binding<Bool>,
        onPendingIncomingCountChange: @escaping (Int) -> Void = { _ in },
        presenceStore: PresenceStore? = nil,
        friendCacheStore: FriendCacheStore? = nil,
        tokenProvider: @escaping () -> String?
    ) {
        _vm = State(
            wrappedValue: ContactsViewModel(
                friendRepo: friendRepo,
                requestRepo: requestRepo,
                tokenProvider: tokenProvider,
                friendCacheStore: friendCacheStore
            )
        )
        self.userRepo = userRepo
        self.presenceStore = presenceStore
        self.tokenProvider = tokenProvider
        self.onPendingIncomingCountChange = onPendingIncomingCountChange
        self._showRequests = showRequests
        self._showSearch = showSearch
    }

    var body: some View {
        FriendsListView(friends: vm.friends, presenceStore: presenceStore)
            .task {
                await vm.refresh()
                reportPendingIncomingCount()
            }
            .refreshable {
                await vm.refresh()
                reportPendingIncomingCount()
            }
            .onChange(of: vm.pendingIncomingCount) { _, newValue in
                onPendingIncomingCountChange(newValue)
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
            .toolbarBackground(Color.echoInteractive, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func refreshAfterSheet() {
        Task {
            await vm.refresh()
            reportPendingIncomingCount()
        }
    }

    private func reportPendingIncomingCount() {
        onPendingIncomingCountChange(vm.pendingIncomingCount)
    }
}
