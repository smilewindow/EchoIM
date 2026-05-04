import SwiftUI

struct FloatingLabelTextField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var error: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrectionDisabled: Bool = true
    var accessibilityId: String? = nil

    @FocusState private var isFocused: Bool

    private var isFloating: Bool { isFocused || !text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.echoSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isFocused ? Color.echoInteractive : Color.echoBlue.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isFocused)

                Text(label)
                    .font(isFloating ? .system(size: 9, weight: .medium) : .body)
                    .foregroundStyle(isFloating ? Color.echoInteractive : Color.echoMuted)
                    .padding(.leading, 14)
                    .padding(.top, isFloating ? 8 : 18)
                    .animation(.easeInOut(duration: 0.15), value: isFloating)

                Group {
                    if isSecure {
                        SecureField("", text: $text)
                            .textContentType(textContentType)
                    } else {
                        TextField("", text: $text)
                            .keyboardType(keyboardType)
                            .textContentType(textContentType)
                    }
                }
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(autocorrectionDisabled)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.top, 26)
                .opacity(isFloating ? 1 : 0)
                .accessibilityIdentifier(accessibilityId ?? "")
            }
            .frame(height: 56)
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.leading, 2)
            }
        }
    }
}

#Preview {
    @Previewable @State var text1 = ""
    @Previewable @State var text2 = "alice"
    @Previewable @State var pw = ""
    VStack(spacing: 16) {
        FloatingLabelTextField(label: "邮箱", text: $text1,
                               keyboardType: .emailAddress,
                               textContentType: .emailAddress,
                               autocapitalization: .never,
                               accessibilityId: "previewEmail")
        FloatingLabelTextField(label: "用户名", text: $text2,
                               autocapitalization: .never,
                               accessibilityId: "previewUsername")
        FloatingLabelTextField(label: "密码", text: $pw,
                               isSecure: true,
                               textContentType: .password,
                               accessibilityId: "previewPassword")
        FloatingLabelTextField(label: "错误示例", text: $text1,
                               error: "邮箱格式不正确",
                               keyboardType: .emailAddress,
                               autocapitalization: .never)
    }
    .padding()
    .background(Color.echoSurface)
}
