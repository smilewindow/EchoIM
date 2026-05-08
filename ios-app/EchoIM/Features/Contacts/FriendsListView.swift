import SwiftUI

struct FriendsListView: View {
    let friends: [Friend]
    let presenceStore: PresenceStore?

    init(friends: [Friend], presenceStore: PresenceStore? = nil) {
        self.friends = friends
        self.presenceStore = presenceStore
    }

    private var onlineFriends: [Friend] {
        friends.filter { presenceStore?.isOnline($0.id) == true }
    }

    private var offlineFriends: [Friend] {
        friends.filter { presenceStore?.isOnline($0.id) != true }
    }

    var body: some View {
        if friends.isEmpty {
            emptyState
        } else {
            List {
                if !onlineFriends.isEmpty {
                    Section("在线 (\(onlineFriends.count))") {
                        ForEach(onlineFriends) { friend in
                            FriendRow(friend: friend, isOnline: true)
                        }
                    }
                }
                if onlineFriends.isEmpty {
                    Section {
                        ForEach(offlineFriends) { friend in
                            FriendRow(friend: friend, isOnline: false)
                        }
                    }
                } else {
                    Section("其他") {
                        ForEach(offlineFriends) { friend in
                            FriendRow(friend: friend, isOnline: false)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("friendsList")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.echoBlue.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.echoBlue)
            }
            Text("还没有好友")
                .font(.headline)
                .foregroundStyle(Color.echoTextDeep)
            Text("点击右上角 + 搜索并添加好友")
                .font(.subheadline)
                .foregroundStyle(Color.echoMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friendsEmpty")
    }
}

private struct FriendRow: View {
    let friend: Friend
    let isOnline: Bool

    var body: some View {
        NavigationLink(value: ChatRoute.peer(friend)) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(profile: friend, size: 42)
                    if isOnline {
                        PresenceDot()
                            .offset(x: 2, y: 2)
                            .accessibilityIdentifier("friendOnlineDot_\(friend.username)")
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.echoTextDeep)
                    Text(isOnline ? "在线" : "离线")
                        .font(.caption)
                        .foregroundStyle(isOnline ? Color.echoOnline : Color.secondary)
                }
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }

                Spacer()

                Text("发消息")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.echoBlue)
            }
        }
        .accessibilityIdentifier("friendRow_\(friend.username)")
    }
}
