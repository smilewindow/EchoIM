import SwiftUI

struct HomePlaceholderView: View {
    let user: AuthenticatedUser
    var onLogout: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("已登录")
                    .font(.title2)

                Text(user.displayName ?? user.username)
                    .font(.headline)
                    .accessibilityIdentifier("homeUsername")

                Text(user.email)
                    .foregroundStyle(.secondary)

                Button("登出") {
                    Task { await onLogout() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("homeLogout")
            }
            .padding()
            .navigationTitle("EchoIM")
        }
    }
}
