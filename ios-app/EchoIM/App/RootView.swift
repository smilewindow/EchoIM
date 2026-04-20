import SwiftUI

struct RootView: View {
    @State private var container: AppContainer = {
        let shouldResetKeychain = CommandLine.arguments.contains("-uitest-reset-keychain")
        let container = AppContainer(resetKeychainOnLaunch: shouldResetKeychain)
        // 需要在首帧前同步恢复登录态，避免先闪登录页再切 Home。
        container.bootstrap()
        return container
    }()

    @State private var showRegister = false

    var body: some View {
        Group {
            if let user = container.currentUser {
                HomePlaceholderView(user: user) {
                    await container.logout()
                    // 登出后统一回登录页，不保留注册页残留状态。
                    showRegister = false
                }
                .task {
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
