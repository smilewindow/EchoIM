import SwiftUI

struct FriendsListView: View {
    let friends: [Friend]
    let presenceStore: PresenceStore?

    /// P6：显式 init 保持向后兼容，presenceStore 默认 nil（P5 既有调用不变）。
    init(friends: [Friend], presenceStore: PresenceStore? = nil) {
        self.friends = friends
        self.presenceStore = presenceStore
    }

    var body: some View {
        if friends.isEmpty {
            emptyState
        } else {
            List(friends) { friend in
                NavigationLink(value: ChatRoute.peer(friend)) {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(profile: friend, size: 40)
                            if presenceStore?.isOnline(friend.id) == true {
                                PresenceDot()
                                    .offset(x: 2, y: 2)
                                    .accessibilityIdentifier("friendOnlineDot_\(friend.username)")
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayTitle)
                                .font(.subheadline.weight(.medium))

                            if let usernameSubtitle = friend.usernameSubtitle {
                                Text(usernameSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("friendRow_\(friend.username)")
            }
            .listStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("friendsList")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有好友")
                .foregroundStyle(.secondary)
            Text("点右上角 + 搜索用户添加好友")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friendsEmpty")
    }
}
