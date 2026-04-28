import SwiftUI

struct UserDetailView: View {
    let profile: UserProfile
    let presenceStore: PresenceStore?

    init(profile: UserProfile, presenceStore: PresenceStore? = nil) {
        self.profile = profile
        self.presenceStore = presenceStore
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AvatarView(profile: profile, size: 120)
                    .padding(.top, 32)
                    .accessibilityIdentifier("userDetailAvatar")

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.displayTitle)
                            .font(.title2.weight(.semibold))
                        if isOnline {
                            PresenceDot(size: 10)
                                .accessibilityIdentifier("userDetailOnlineDot")
                        }
                    }
                    .accessibilityIdentifier("userDetailDisplayTitle")

                    if let subtitle = profile.usernameSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("@\(profile.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(isOnline ? "在线" : "离线")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("资料")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("userDetailRoot")
    }

    private var isOnline: Bool {
        presenceStore?.isOnline(profile.id) == true
    }
}
