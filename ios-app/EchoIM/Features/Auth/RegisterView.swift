import SwiftUI

struct RegisterView: View {
    @Bindable var vm: RegisterViewModel
    var onBackToLogin: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                field("邀请码", text: $vm.inviteCode, error: vm.inviteCodeError, id: "regInvite")
                field("用户名", text: $vm.username, error: vm.usernameError, id: "regUsername")
                field(
                    "邮箱",
                    text: $vm.email,
                    error: vm.emailError,
                    id: "regEmail",
                    keyboard: .emailAddress,
                    contentType: .emailAddress
                )
                secureField("密码", text: $vm.password, error: vm.passwordError, id: "regPassword")

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        if case .submitting = vm.state {
                            ProgressView()
                        } else {
                            Text("注册")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.state == .submitting)
                    .accessibilityIdentifier("regSubmit")
                }

                Section {
                    Button("已有账号？返回登录", action: onBackToLogin)
                        .accessibilityIdentifier("regGoLogin")
                }
            }
            .navigationTitle("注册")
            .alert(
                "注册失败",
                isPresented: Binding(
                    get: { vm.toast != nil },
                    set: { if !$0 { vm.toast = nil } }
                ),
                presenting: vm.toast
            ) { _ in
                Button("好", role: .cancel) {
                    vm.toast = nil
                }
                .accessibilityIdentifier("regToastOK")
            } message: { message in
                Text(message)
            }
        }
    }

    /// 用户名 / 邮箱 / 邀请码都要求精确输入，默认禁用自动首字母大写。
    @ViewBuilder
    private func field(
        _ title: String,
        text: Binding<String>,
        error: String?,
        id: String,
        autocap: TextInputAutocapitalization = .never,
        keyboard: UIKeyboardType = .default,
        contentType: UITextContentType? = nil
    ) -> some View {
        Section(title) {
            TextField(title, text: text)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .textContentType(contentType)
                .accessibilityIdentifier(id)
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private func secureField(
        _ title: String,
        text: Binding<String>,
        error: String?,
        id: String
    ) -> some View {
        Section(title) {
            SecureField(title, text: text)
                .textContentType(.newPassword)
                .accessibilityIdentifier(id)
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }
}
