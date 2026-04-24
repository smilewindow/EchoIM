import SwiftUI

struct RootView: View {
    @State private var container: AppContainer = {
        let shouldResetKeychain = CommandLine.arguments.contains("-uitest-reset-keychain")
        let container = AppContainer(resetKeychainOnLaunch: shouldResetKeychain)
        // 与 P1 保持一致：首帧同步恢复登录占位，无闪烁。
        container.bootstrap()
        return container
    }()

    @State private var showRegister = false
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
                    await container.refreshCurrentUser()
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
        .onChange(of: scenePhase) { _, newPhase in
            guard container.currentUser != nil else { return }
            switch newPhase {
            case .active:
                container.connectWebSocketIfNeeded()
            case .background:
                container.session?.disconnectWebSocket(reason: .userInitiated)
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
}
