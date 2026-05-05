import SwiftUI

struct LoginView: View {
    @Bindable var vm: LoginViewModel
    var onNavigateToRegister: () -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.echoBlue,
                        Color(red: 22/255, green: 78/255, blue: 99/255),
                        Color(red: 14/255, green: 58/255, blue: 74/255),
                    ],
                    startPoint: UnitPoint(x: 0.67, y: 0.0),
                    endPoint: UnitPoint(x: 0.33, y: 1.0)
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    heroSection
                    Spacer()
                    Color.clear.frame(height: 420)
                }

                formCard
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .navigationBarHidden(true)
            .alert(
                "登录失败",
                isPresented: Binding(
                    get: { vm.toast != nil },
                    set: { if !$0 { vm.toast = nil } }
                ),
                presenting: vm.toast
            ) { _ in
                Button("好", role: .cancel) { vm.toast = nil }
                    .accessibilityIdentifier("loginToastOK")
            } message: { msg in
                Text(msg)
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("EchoIM")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Real-time messaging")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("欢迎回来")
                .font(.title3.bold())
                .foregroundStyle(Color.echoTextDeep)

            FloatingLabelTextField(
                label: "邮箱",
                text: $vm.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never,
                accessibilityId: "loginEmail"
            )

            FloatingLabelTextField(
                label: "密码",
                text: $vm.password,
                isSecure: true,
                textContentType: .password,
                accessibilityId: "loginPassword"
            )

            Button {
                dismissKeyboard()
                Task { await vm.submit() }
            } label: {
                Group {
                    if case .submitting = vm.state {
                        ProgressView().tint(.white)
                    } else {
                        Text("登录")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .background(Color.echoInteractive, in: RoundedRectangle(cornerRadius: 12))
            .disabled(vm.state == .submitting)
            .accessibilityIdentifier("loginSubmit")

            HStack {
                Spacer()
                Button("没有账号？立即注册", action: onNavigateToRegister)
                    .font(.subheadline)
                    .foregroundStyle(Color.echoBlue)
                    .accessibilityIdentifier("loginGoRegister")
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, max(24, 0))
        .frame(maxWidth: .infinity)
        .background(
            Color(uiColor: .systemBackground)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 24
                ))
        )
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func dismissKeyboard() {
        // FloatingLabelTextField 自己持有焦点；这里直接让当前输入控件放弃 first responder。
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
