import SwiftUI

struct UserSearchSheetView: View {
    @Bindable var vm: ContactsViewModel
    let userRepo: UserRepository
    let tokenProvider: () -> String?
    var onClose: () -> Void

    @State private var query = ""
    @State private var results: [UserProfile] = []
    @State private var isSearching = false
    @State private var sendingId: Int?
    @State private var errorToast: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                list
            }
            .navigationTitle("添加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        onClose()
                    }
                }
            }
            .alert(
                item: Binding(
                    get: { errorToast.map { ErrorWrapper(message: $0) } },
                    set: { errorToast = $0?.message }
                )
            ) { wrapper in
                Alert(
                    title: Text("发送失败"),
                    message: Text(wrapper.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("输入用户名搜索", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: query) { _, newValue in
                    searchTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespaces)

                    if trimmed.count < 2 {
                        results = []
                        return
                    }

                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)

                        if Task.isCancelled {
                            return
                        }

                        await performSearch(trimmed)
                    }
                }

            if !query.isEmpty {
                Button(action: {
                    query = ""
                    results = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding()
    }

    @ViewBuilder
    private var list: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
            emptyHint("至少输入两个字符")
        } else if results.isEmpty {
            emptyHint("没有匹配的用户")
        } else {
            List(results) { user in
                HStack(spacing: 12) {
                    AvatarView(profile: user, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName ?? user.username)
                            .font(.subheadline.weight(.medium))

                        if user.displayName != nil {
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(buttonLabel(for: user)) {
                        sendingId = user.id
                        Task {
                            let result = await vm.send(recipientId: user.id)
                            sendingId = nil

                            if case .failure(let error) = result {
                                errorToast = String(describing: error)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAlreadySent(user.id) || sendingId == user.id)
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }

    private func buttonLabel(for user: UserProfile) -> String {
        if isAlreadySent(user.id) {
            return "已发送"
        }

        if sendingId == user.id {
            return "…"
        }

        return "添加"
    }

    private func isAlreadySent(_ userId: Int) -> Bool {
        vm.sent.contains { $0.recipientId == userId }
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performSearch(_ trimmed: String) async {
        guard let token = tokenProvider() else {
            return
        }

        isSearching = true
        defer {
            isSearching = false
        }

        do {
            results = try await userRepo.searchUsers(query: trimmed, token: token)
        } catch {
            results = []
        }
    }

    private struct ErrorWrapper: Identifiable {
        let message: String

        var id: String {
            message
        }
    }
}
