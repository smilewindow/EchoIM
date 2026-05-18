import SwiftUI

struct ToastOverlay: View {
    let toast: ToastMessage

    var body: some View {
        Text(toast.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.78), in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
            .padding(.horizontal, 32)
            .accessibilityIdentifier("globalToast")
    }
}
