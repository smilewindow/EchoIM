import SwiftUI

struct RootView: View {
    let container: AppContainer

    @State private var showRegister = false
    @State private var sessionExpiredToastVisible = false
    @State private var toastDismissTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if container.currentUser != nil {
                MainTabView(container: container) {
                    await container.logout()
                    showRegister = false
                }
                .task {
                    container.connectWebSocketIfNeeded()
                }
            } else if showRegister {
                RegisterView(vm: makeRegisterViewModel()) {
                    showRegister = false
                }
            } else {
                LoginView(vm: makeLoginViewModel()) {
                    showRegister = true
                }
            }
        }
        .animation(.default, value: container.currentUser?.id)
        .animation(.default, value: showRegister)
        .overlay {
            if sessionExpiredToastVisible {
                sessionExpiredToast("登录状态已失效，请重新登录")
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: sessionExpiredToastVisible)
        .onChange(of: container.sessionExpiredNoticeID) { _, noticeID in
            toastDismissTask?.cancel()
            guard noticeID != nil else {
                sessionExpiredToastVisible = false
                return
            }

            sessionExpiredToastVisible = true
            toastDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled {
                    sessionExpiredToastVisible = false
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard let session = container.session else { return }
            switch newPhase {
            case .active:
                session.connectWebSocketIfNeeded()
            case .background:
                session.disconnectWebSocket(reason: .userInitiated)
            case .inactive:
                // 通知中心 / 锁屏瞬间等过渡态，保持当前连接状态。
                break
            @unknown default:
                break
            }
        }
    }

    private func makeLoginViewModel() -> LoginViewModel {
        LoginViewModel(repo: container.makeAuthRepository()) { response in
            container.handleLoginSuccess(response)
        }
    }

    private func makeRegisterViewModel() -> RegisterViewModel {
        RegisterViewModel(repo: container.makeAuthRepository()) { response in
            container.handleLoginSuccess(response)
            showRegister = false
        }
    }

    private func sessionExpiredToast(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.78), in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
            .padding(.horizontal, 32)
            .accessibilityIdentifier("sessionExpiredToast")
    }
}
