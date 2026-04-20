import SwiftUI

struct LoginView: View {
    @Bindable var vm: LoginViewModel
    var onNavigateToRegister: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("邮箱") {
                    TextField("you@example.com", text: $vm.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("loginEmail")
                }

                Section("密码") {
                    SecureField("至少 8 位", text: $vm.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("loginPassword")
                }

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        if case .submitting = vm.state {
                            ProgressView()
                        } else {
                            Text("登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.state == .submitting)
                    .accessibilityIdentifier("loginSubmit")
                }

                Section {
                    Button("没有账号？去注册", action: onNavigateToRegister)
                        .accessibilityIdentifier("loginGoRegister")
                }
            }
            .navigationTitle("登录")
            // 登录错误统一走弹窗提示，不做页内红字。
            .alert(
                "登录失败",
                isPresented: Binding(
                    get: { vm.toast != nil },
                    set: { if !$0 { vm.toast = nil } }
                ),
                presenting: vm.toast
            ) { _ in
                Button("好", role: .cancel) {
                    vm.toast = nil
                }
                .accessibilityIdentifier("loginToastOK")
            } message: { message in
                Text(message)
            }
        }
    }
}
