import SwiftUI

struct MeRow: View {
    let iconName: String
    let iconColor: Color
    let title: String
    var isDestructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                Text(title)
                    .foregroundStyle(isDestructive ? Color.echoDanger : Color.echoTextDeep)
                    .font(.body)

                Spacer()

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.echoMuted)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 0) {
        MeRow(iconName: "person.crop.circle", iconColor: .echoBlue, title: "编辑资料") {}
        Divider().padding(.leading, 56)
        MeRow(iconName: "trash", iconColor: .echoDanger, title: "清除聊天缓存", isDestructive: true) {}
        Divider().padding(.leading, 56)
        MeRow(iconName: "arrow.right.square", iconColor: .echoDanger, title: "登出", isDestructive: true) {}
    }
    .padding(.horizontal, 16)
    .background(Color(uiColor: .systemBackground))
    .cornerRadius(14)
    .padding()
}
