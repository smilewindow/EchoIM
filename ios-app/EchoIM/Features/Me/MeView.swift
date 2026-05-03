import SwiftUI

struct MeView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var showClearCacheConfirm = false
    @State private var isClearing = false

    var body: some View {
        Group {
            if let user = container.currentUser {
                Form {
                    Section {
                        HStack(spacing: 16) {
                            AvatarView(user: user, size: 72)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayTitle)
                                    .font(.title3.weight(.semibold))
                                    .accessibilityIdentifier("homeUsername")

                                if let usernameSubtitle = user.usernameSubtitle {
                                    Text(usernameSubtitle)
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

                    // P7：编辑资料入口
                    Section {
                        NavigationLink {
                            ProfileEditView(
                                username: user.username,
                                viewModel: makeProfileEditViewModel()
                            )
                        } label: {
                            Label("编辑资料", systemImage: "person.crop.circle")
                        }
                        .accessibilityIdentifier("meEditProfile")
                    }

                    Section {
                        Button(role: .destructive) {
                            showClearCacheConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("清除聊天缓存")
                            }
                        }
                        .accessibilityIdentifier("meClearCache")
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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "清除本地聊天缓存？",
            isPresented: $showClearCacheConfirm,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task {
                    isClearing = true
                    await container.clearChatCache()
                    isClearing = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除本设备上缓存的消息与图片。服务器上的消息不受影响。")
        }
        .overlay(alignment: .center) {
            if isClearing {
                ProgressView("清除中…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// VM 的依赖全部从 container 取；currentUser setter 直接写 container.currentUser，
    /// 让 SwiftUI 沿 @Observable 链路重渲染（不变式 5）。
    @MainActor
    private func makeProfileEditViewModel() -> ProfileEditViewModel {
        ProfileEditViewModel(
            currentUser: { container.currentUser },
            currentUserSetter: { container.currentUser = $0 },
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            },
            userRepo: container.makeUserRepository(),
            uploadRepo: container.session?.makeUploadRepository()
                ?? UploadRepositoryImpl(api: container.apiClient),
            refreshCurrentUser: { [weak container] in
                await container?.refreshCurrentUser()
            },
            onUnauthorized: { [weak container] in
                await container?.handleUnauthorized()
            }
        )
    }
}
