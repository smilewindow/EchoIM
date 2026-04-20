import SwiftUI

struct MeView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    var body: some View {
        NavigationStack {
            if let user = container.currentUser {
                Form {
                    Section {
                        HStack(spacing: 16) {
                            AvatarView(user: user, size: 72)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName ?? user.username)
                                    .font(.title3.weight(.semibold))
                                    .accessibilityIdentifier("homeUsername")

                                if user.displayName != nil {
                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if !user.email.isEmpty {
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        Button(role: .destructive) {
                            Task { await onLogout() }
                        } label: {
                            HStack {
                                Spacer()
                                Text("登出")
                                Spacer()
                            }
                        }
                        .accessibilityIdentifier("homeLogout")
                    }
                }
                .navigationTitle("我")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
