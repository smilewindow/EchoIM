import SwiftUI

extension Color {
    // MARK: - Light/dark adaptive init
    init(light: Color, dark: Color) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    // MARK: - Static tokens
    /// #0891B2 — 渐变起点、弱强调背景（不承载白字）
    static let echoBlue = Color(red: 8/255, green: 145/255, blue: 178/255)

    /// #0E7490 — 按钮、导航栏背景（白字对比度 5.2:1，WCAG AA）
    static let echoInteractive = Color(red: 14/255, green: 116/255, blue: 144/255)

    /// #22D3EE — 渐变终点、高亮
    static let echoCyan = Color(red: 34/255, green: 211/255, blue: 238/255)

    /// 在线状态（= iOS 系统绿 #34C759）
    static let echoOnline = Color(red: 52/255, green: 199/255, blue: 89/255)

    /// 未读角标、发送失败（= iOS 系统红 #FF3B30）
    static let echoDanger = Color(red: 255/255, green: 59/255, blue: 48/255)

    /// 页面背景、输入框底色（深色模式：#0C1A1F）
    static let echoSurface = Color(
        light: Color(red: 236/255, green: 254/255, blue: 255/255),
        dark: Color(red: 12/255, green: 26/255, blue: 31/255)
    )

    /// 标题、主文字（深色模式：#A5F3FC）
    static let echoTextDeep = Color(
        light: Color(red: 22/255, green: 78/255, blue: 99/255),
        dark: Color(red: 165/255, green: 243/255, blue: 252/255)
    )

    /// 副文字、时间戳（深色模式：#5BA3B0）
    static let echoMuted = Color(
        light: Color(red: 51/255, green: 124/255, blue: 138/255),
        dark: Color(red: 91/255, green: 163/255, blue: 176/255)
    )

    // MARK: - Gradient shorthands
    static var echoMainGradient: LinearGradient {
        LinearGradient(
            colors: [.echoBlue, .echoCyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var echoButtonGradient: LinearGradient {
        LinearGradient(
            colors: [.echoInteractive, .echoBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Avatar hash gradients (8 套，index = username hash % 8)
    static func avatarGradient(for username: String) -> LinearGradient {
        let index = username.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 8
        let pairs: [(Color, Color)] = [
            (.echoBlue, .echoCyan),                                                               // 0 青蓝
            (Color(red: 124/255, green: 58/255, blue: 237/255),
             Color(red: 167/255, green: 139/255, blue: 250/255)),                                 // 1 紫
            (Color(red: 225/255, green: 29/255, blue: 72/255),
             Color(red: 251/255, green: 113/255, blue: 133/255)),                                 // 2 玫瑰
            (Color(red: 217/255, green: 119/255, blue: 6/255),
             Color(red: 252/255, green: 211/255, blue: 77/255)),                                  // 3 琥珀
            (Color(red: 5/255, green: 150/255, blue: 105/255),
             Color(red: 52/255, green: 211/255, blue: 153/255)),                                  // 4 绿
            (Color(red: 14/255, green: 165/255, blue: 233/255),
             Color(red: 125/255, green: 211/255, blue: 252/255)),                                 // 5 天蓝
            (Color(red: 220/255, green: 38/255, blue: 38/255),
             Color(red: 248/255, green: 113/255, blue: 113/255)),                                 // 6 红
            (Color(red: 124/255, green: 58/255, blue: 237/255),
             Color(red: 196/255, green: 181/255, blue: 253/255)),                                 // 7 淡紫
        ]
        let (start, end) = pairs[index]
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
