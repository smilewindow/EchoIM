import SwiftUI

struct FriendRequestsSheetView: View {
    @Bindable var vm: ContactsViewModel
    var onClose: () -> Void

    @State private var respondingId: Int?

    var body: some View {
        NavigationStack {
            List {
                if !vm.incoming.isEmpty {
                    Section("待处理") {
                        ForEach(vm.incoming) { request in
                            incomingRow(request)
                        }
                    }
                }

                if !vm.sent.isEmpty {
                    Section("已发送") {
                        ForEach(vm.sent) { request in
                            sentRow(request)
                        }
                    }
                }

                if !vm.history.isEmpty {
                    Section("历史") {
                        ForEach(vm.history) { request in
                            historyRow(request)
                        }
                    }
                }

                if vm.incoming.isEmpty && vm.sent.isEmpty && vm.history.isEmpty {
                    Text("暂无好友申请")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("好友申请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onClose()
                    }
                }
            }
            .refreshable {
                await vm.loadRequestDetails()
            }
            .task {
                await vm.loadRequestDetails()
            }
        }
    }

    private func incomingRow(_ request: FriendRequest) -> some View {
        HStack(spacing: 12) {
            avatarFor(request)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayTitle(fallback: String(localized: "用户 \(request.senderId)")))
                    .font(.subheadline.weight(.medium))

                if let usernameSubtitle = request.usernameSubtitle {
                    Text(usernameSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button("同意") {
                    respondingId = request.id
                    Task {
                        await vm.respond(requestId: request.id, accept: true)
                        respondingId = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(respondingId == request.id)
                .accessibilityIdentifier("acceptFriendRequest_\(request.username ?? "\(request.senderId)")")

                Button("拒绝") {
                    respondingId = request.id
                    Task {
                        await vm.respond(requestId: request.id, accept: false)
                        respondingId = nil
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(respondingId == request.id)
                .accessibilityIdentifier("declineFriendRequest_\(request.username ?? "\(request.senderId)")")
            }
        }
        .accessibilityIdentifier("incomingFriendRequest_\(request.username ?? "\(request.senderId)")")
    }

    private func sentRow(_ request: FriendRequest) -> some View {
        HStack(spacing: 12) {
            avatarFor(request)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayTitle(fallback: String(localized: "用户 \(request.recipientId)")))
                    .font(.subheadline.weight(.medium))

                if let usernameSubtitle = request.usernameSubtitle {
                    Text(usernameSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("等待接受")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("sentFriendRequest_\(request.username ?? "\(request.recipientId)")")
    }

    private func historyRow(_ request: FriendRequest) -> some View {
        HStack(spacing: 12) {
            avatarFor(request)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayTitle())
                    .font(.subheadline)
                Text(request.status == .accepted ? String(localized: "已接受") : String(localized: "已拒绝"))
                    .font(.caption)
                    .foregroundStyle(request.status == .accepted ? .green : .red)
            }

            Spacer()

            if let direction = request.direction {
                Text(direction == "sent" ? String(localized: "发送") : String(localized: "收到"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(
            "historyFriendRequest_\(request.direction ?? "unknown")_\(request.username ?? "user")_\(request.status.rawValue)"
        )
    }

    private func avatarFor(_ request: FriendRequest) -> some View {
        let profile = UserProfile(
            id: 0,
            username: request.username ?? "?",
            displayName: request.displayName,
            avatarUrl: request.avatarUrl
        )
        return AvatarView(profile: profile, size: 40)
    }
}
