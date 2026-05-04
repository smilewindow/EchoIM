import SwiftUI

struct RegisterView: View {
    @Bindable var vm: RegisterViewModel
    var onBackToLogin: () -> Void

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
                    Color.clear.frame(height: 540)
                }

                formCard
            }
            .navigationBarHidden(true)
            .alert(
                "注册失败",
                isPresented: Binding(
                    get: { vm.toast != nil },
                    set: { if !$0 { vm.toast = nil } }
                ),
                presenting: vm.toast
            ) { _ in
                Button("好", role: .cancel) { vm.toast = nil }
                    .accessibilityIdentifier("regToastOK")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("创建账号")
                    .font(.title3.bold())
                    .foregroundStyle(Color.echoTextDeep)

                FloatingLabelTextField(
                    label: "邀请码",
                    text: $vm.inviteCode,
                    error: vm.inviteCodeError,
                    autocapitalization: .never,
                    accessibilityId: "regInvite"
                )
                FloatingLabelTextField(
                    label: "用户名",
                    text: $vm.username,
                    error: vm.usernameError,
                    autocapitalization: .never,
                    accessibilityId: "regUsername"
                )
                FloatingLabelTextField(
                    label: "邮箱",
                    text: $vm.email,
                    error: vm.emailError,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    autocapitalization: .never,
                    accessibilityId: "regEmail"
                )
                FloatingLabelTextField(
                    label: "密码",
                    text: $vm.password,
                    error: vm.passwordError,
                    isSecure: true,
                    textContentType: .newPassword,
                    accessibilityId: "regPassword"
                )

                Button {
                    Task { await vm.submit() }
                } label: {
                    Group {
                        if case .submitting = vm.state {
                            ProgressView().tint(.white)
                        } else {
                            Text("注册")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .background(Color.echoInteractive, in: RoundedRectangle(cornerRadius: 12))
                .disabled(vm.state == .submitting)
                .accessibilityIdentifier("regSubmit")

                HStack {
                    Spacer()
                    Button("已有账号？返回登录", action: onBackToLogin)
                        .font(.subheadline)
                        .foregroundStyle(Color.echoBlue)
                        .accessibilityIdentifier("regGoLogin")
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
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
}
