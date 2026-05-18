import SwiftUI

struct RootView: View {
    let container: AppContainer

    @State private var showLaunchSplash = true
    @State private var didStartLaunchSequence = false
    @State private var showRegister = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
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

            if showLaunchSplash {
                LaunchSplashView()
                    .transition(.opacity)
                    .zIndex(1)
                    .allowsHitTesting(true)
            }
        }
        .task {
            guard !didStartLaunchSequence else { return }
            didStartLaunchSequence = true

            try? await Task.sleep(nanoseconds: launchSplashDuration)
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.28)) {
                showLaunchSplash = false
            }
        }
        .animation(.default, value: container.currentUser?.id)
        .animation(.default, value: showRegister)
        .overlay {
            if let toast = container.toastCenter.current {
                ToastOverlay(toast: toast)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: container.toastCenter.current?.id)
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

    private var launchSplashDuration: UInt64 {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-uitest-launch-splash-duration"),
           arguments.indices.contains(index + 1),
           let seconds = Double(arguments[index + 1]) {
            return UInt64(seconds * 1_000_000_000)
        }
        return 1_500_000_000
    }
}
