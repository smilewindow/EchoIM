import SwiftUI

struct FriendsListView: View {
    let friends: [Friend]

    var body: some View {
        if friends.isEmpty {
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
        } else {
            List(friends) { friend in
                NavigationLink(value: ChatRoute.peer(friend)) {
                    HStack(spacing: 12) {
                        AvatarView(profile: friend, size: 40)

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
}
