import NukeUI
import SwiftUI

struct AvatarView: View {
    let displayName: String?
    let username: String
    let avatarUrl: String?
    var size: CGFloat = 40

    init(profile: UserProfile, size: CGFloat = 40) {
        self.displayName = profile.displayName
        self.username = profile.username
        self.avatarUrl = profile.avatarUrl
        self.size = size
    }

    init(user: AuthenticatedUser, size: CGFloat = 40) {
        self.displayName = user.displayName
        self.username = user.username
        self.avatarUrl = user.avatarUrl
        self.size = size
    }

    var body: some View {
        Group {
            if let url = Endpoints.absolute(avatarUrl) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if state.error != nil {
                        initialsPlaceholder
                    } else {
                        initialsPlaceholder
                            .overlay(ProgressView().scaleEffect(0.6))
                    }
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let preferredName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (preferredName?.isEmpty == false ? preferredName! : username)
        return String(base.prefix(2)).uppercased()
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)

            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
