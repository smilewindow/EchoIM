import SwiftUI

struct MeView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var showClearCacheConfirm = false
    @State private var isClearing = false
    @State private var showLogViewer = false

    var body: some View {
        Group {
            if let user = container.currentUser {
                ScrollView {
                    VStack(spacing: 16) {
                        if container.isRestoringCurrentUser && isRestoringPlaceholder(user) {
                            restoringUserInfoCard
                        } else {
                            userInfoCard(user: user)
                            editProfileCard(user: user)
                        }
                        cacheCard
                        logoutCard

                        Text("EchoIM v\(appVersion)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .onLongPressGesture(minimumDuration: 0.5) {
                                showLogViewer = true
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await container.refreshCurrentUserIfRestoring()
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
        .sheet(isPresented: $showLogViewer) {
            NavigationStack {
                LogViewer()
                    .navigationTitle("日志")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .toolbarBackground(Color.echoInteractive, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - 资料恢复中卡片
    private var restoringUserInfoCard: some View {
        userHeaderCard {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))

            VStack(spacing: 4) {
                Text("资料暂不可用")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("homeUsername")

                Text("服务恢复后会自动同步")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
    }

    // MARK: - 用户信息卡片
    private func userInfoCard(user: AuthenticatedUser) -> some View {
        userHeaderCard {
            AvatarView(user: user, size: 56)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))

            VStack(spacing: 4) {
                Text(user.displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("homeUsername")

                if let sub = user.usernameSubtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.65))
                }

                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - 资料卡片外壳
    private func userHeaderCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.echoMainGradient)
        )
    }

    // MARK: - 编辑资料卡片
    private func editProfileCard(user: AuthenticatedUser) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                ProfileEditView(
                    username: user.username,
                    viewModel: makeProfileEditViewModel()
                )
            } label: {
                MeRow(
                    iconName: "person.crop.circle",
                    iconColor: Color.echoBlue,
                    title: "编辑资料"
                ) {}
                    .allowsHitTesting(false)
            }
            .accessibilityIdentifier("meEditProfile")
            .padding(.horizontal, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    // MARK: - 缓存卡片
    private var cacheCard: some View {
        VStack(spacing: 0) {
            MeRow(
                iconName: "trash",
                iconColor: Color.echoDanger,
                title: "清除聊天缓存",
                isDestructive: true
            ) {
                showClearCacheConfirm = true
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("meClearCache")
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    // MARK: - 登出卡片
    private var logoutCard: some View {
        VStack(spacing: 0) {
            MeRow(
                iconName: "arrow.right.square",
                iconColor: Color.echoDanger,
                title: "登出",
                isDestructive: true
            ) {
                Task { await onLogout() }
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("homeLogout")
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @MainActor
    private func makeProfileEditViewModel() -> ProfileEditViewModel {
        ProfileEditViewModel(
            currentUser: { container.currentUser },
            currentUserSetter: { container.updateCurrentUser($0) },
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

    private func isRestoringPlaceholder(_ user: AuthenticatedUser) -> Bool {
        user.username == "(restoring)" && user.email.isEmpty
    }
}
