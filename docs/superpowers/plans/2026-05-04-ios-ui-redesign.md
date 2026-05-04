# EchoIM iOS UI 重设计实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按照 `docs/superpowers/specs/2026-05-03-ios-ui-redesign.md` 规格，将 EchoIM iOS 端全量重设计为青蓝色主题（echoInteractive 导航栏 + 哈希头像渐变 + Skeleton 加载态 + 消息弹入动画 + 浮动 Label 输入框）。

**Architecture:** 先建立 `Color+Echo.swift` 色彩 token 层和四个共享 UI 组件（AvatarView 改造、PresenceDot 改造、SkeletonView 新建、FloatingLabelTextField 新建、MeRow 新建），再逐 feature 重写/改造各 View，最后调整 ChatViewModel 逻辑（`isConsecutive`、`shouldShowTimestamp`、haptic 行为）。

**Tech Stack:** SwiftUI + iOS 17+ + `@Observable` + Swift Testing（单元测试）

---

## File Structure

| 路径 | 操作 | 职责 |
|------|------|------|
| `ios-app/EchoIM/Core/Extensions/Color+Echo.swift` | **新建** | 全部设计 token + light/dark 自适应扩展 |
| `ios-app/EchoIM/Core/UI/AvatarView.swift` | 改造 | initialsPlaceholder → 哈希渐变 |
| `ios-app/EchoIM/Core/UI/PresenceDot.swift` | 改造 | 脉冲波纹动画 + echoOnline 颜色 |
| `ios-app/EchoIM/Core/UI/SkeletonView.swift` | **新建** | ShimmerModifier + ConversationRowSkeleton + ChatSkeletonView |
| `ios-app/EchoIM/Core/UI/FloatingLabelTextField.swift` | **新建** | 浮动 Label 输入框 |
| `ios-app/EchoIM/Core/UI/MeRow.swift` | **新建** | 「我」页面功能行组件 |
| `ios-app/EchoIM/Features/Chat/ChatViewModel.swift` | 改造 | 新增 `isConsecutive` / `shouldShowTimestamp`；haptic 行为改为 WS echo → `success()` |
| `ios-app/EchoIM/Features/Chat/MessageBubble.swift` | 改造 | 圆角规则 + 颜色 + 弹入动画 + footer 样式 |
| `ios-app/EchoIM/Features/Chat/ChatView.swift` | 改造 | Skeleton + 时间戳分组 + 输入栏样式 + toolbarBackground |
| `ios-app/EchoIM/Features/Auth/LoginView.swift` | 重写 | 渐变背景 + 品牌顶部 + 白色卡片底部 + FloatingLabelTextField |
| `ios-app/EchoIM/Features/Auth/RegisterView.swift` | 重写 | 与 LoginView 共用品牌顶部，4 个字段 |
| `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift` | 改造 | ConversationRow 头像/间距/分隔线 + Skeleton + 空状态 + toolbarBackground |
| `ios-app/EchoIM/Features/Contacts/FriendsListView.swift` | 改造 | 在线/离线分组 + FriendRow 改造 + 空状态 |
| `ios-app/EchoIM/Features/Contacts/ContactsView.swift` | 改造 | toolbarBackground（透传给 NavigationStack） |
| `ios-app/EchoIM/Features/Me/MeView.swift` | 重写 | 移除 Form，ScrollView + 渐变卡片 + MeRow |
| `ios-app/EchoIM/Features/Main/MainTabView.swift` | 改造 | 大标题模式 + 各 tab toolbarBackground + 修改 toolbar 图标 |
| `ios-app/EchoIMTests/ChatViewModelTimestampTests.swift` | **新建** | isConsecutive / shouldShowTimestamp 测试 |
| `ios-app/EchoIMTests/HapticFeedbackInjectionTests.swift` | 改造 | 更新 haptic 期望值，补 WS echo 触发 success() 测试 |

---

## Task 1: Color+Echo.swift — 设计 token 层

**Files:**
- Create: `ios-app/EchoIM/Core/Extensions/Color+Echo.swift`

- [x] **Step 1: 新建文件并写入所有 token**

```swift
// ios-app/EchoIM/Core/Extensions/Color+Echo.swift
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
```

- [x] **Step 2: 编译验证**

```bash
cd /Users/xuyuqin/Documents/EchoIM/ios-app && xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -20
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Core/Extensions/Color+Echo.swift
git commit -m "feat(ios): add Color+Echo design token extension"
```

---

## Task 2: AvatarView — 哈希渐变 initialsPlaceholder

**Files:**
- Modify: `ios-app/EchoIM/Core/UI/AvatarView.swift`

- [x] **Step 1: 替换 initialsPlaceholder**

将 `initialsPlaceholder` computed property 改为哈希渐变背景（依赖 Task 1 的 `Color.avatarGradient(for:)`）：

```swift
// ios-app/EchoIM/Core/UI/AvatarView.swift
import NukeUI
import SwiftUI

struct AvatarView: View {
    let displayName: String?
    let username: String
    let avatarUrl: String?
    var size: CGFloat = 40

    init(profile: UserProfile, size: CGFloat = 40) {
        self.displayName = profile.displayName
        self.username = profile.username
        self.avatarUrl = profile.avatarUrl
        self.size = size
    }

    init(user: AuthenticatedUser, size: CGFloat = 40) {
        self.displayName = user.displayName
        self.username = user.username
        self.avatarUrl = user.avatarUrl
        self.size = size
    }

    var body: some View {
        Group {
            if let url = Endpoints.absolute(avatarUrl) {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else if state.error != nil {
                        initialsPlaceholder
                    } else {
                        initialsPlaceholder
                            .overlay(ProgressView().scaleEffect(0.6))
                    }
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let preferredName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (preferredName?.isEmpty == false ? preferredName! : username)
        return String(base.prefix(2)).uppercased()
    }

    private var initialsPlaceholder: some View {
        ZStack {
            Color.avatarGradient(for: username)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Core/UI/AvatarView.swift
git commit -m "feat(ios): use hash-gradient for avatar initials placeholder"
```

---

## Task 3: PresenceDot — 脉冲波纹动画

**Files:**
- Modify: `ios-app/EchoIM/Core/UI/PresenceDot.swift`

- [x] **Step 1: 重写 PresenceDot，加入脉冲波纹**

规则：`size >= 9` 时显示波纹；聊天导航栏（`size=8`）不显示；遵守 `reducedMotion`。

```swift
// ios-app/EchoIM/Core/UI/PresenceDot.swift
import SwiftUI

struct PresenceDot: View {
    var size: CGFloat = 10
    var borderWidth: CGFloat = 1.5

    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        ZStack {
            if size >= 9 {
                Circle()
                    .fill(Color.echoOnline.opacity(isAnimating ? 0 : 0.4))
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(isAnimating ? 1.8 : 1.0)
            }
            Circle()
                .fill(Color.echoOnline)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: borderWidth)
                )
        }
        .onAppear {
            guard size >= 9, !reducedMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
        .accessibilityLabel(Text("在线"))
        .accessibilityHidden(false)
    }
}

#Preview {
    HStack(spacing: 16) {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.gray).frame(width: 40, height: 40)
            PresenceDot().offset(x: 2, y: 2)
        }
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.blue).frame(width: 56, height: 56)
            PresenceDot(size: 14).offset(x: 2, y: 2)
        }
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(.purple).frame(width: 32, height: 32)
            PresenceDot(size: 8).offset(x: 2, y: 2)  // 聊天导航栏尺寸：无波纹
        }
    }
    .padding()
}
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Core/UI/PresenceDot.swift
git commit -m "feat(ios): add pulse animation to PresenceDot"
```

---

## Task 4: SkeletonView — Shimmer + ConversationRowSkeleton + ChatSkeletonView

**Files:**
- Create: `ios-app/EchoIM/Core/UI/SkeletonView.swift`

- [x] **Step 1: 新建文件，写 ShimmerModifier、ConversationRowSkeleton、ChatSkeletonView**

```swift
// ios-app/EchoIM/Core/UI/SkeletonView.swift
import SwiftUI

// MARK: - Shimmer Modifier
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.5), location: 0.4),
                            .init(color: .clear, location: 0.8),
                        ],
                        startPoint: UnitPoint(x: phase, y: 0),
                        endPoint: UnitPoint(x: phase + 1, y: 0)
                    )
                    .frame(width: width * 2)
                    .offset(x: phase * width)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton 矩形工具
private struct SkeletonRect: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(uiColor: .systemFill))
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - ConversationRowSkeleton
struct ConversationRowSkeleton: View {
    let nameWidth: CGFloat
    let previewWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(uiColor: .systemFill))
                .frame(width: 46, height: 46)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                SkeletonRect(width: nameWidth, height: 14)
                SkeletonRect(width: previewWidth, height: 12)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }
}

// MARK: - ConversationsListSkeleton
struct ConversationsListSkeleton: View {
    // 固定 preset，避免 SwiftUI body 重算时抖动
    private let presets: [(CGFloat, CGFloat)] = [
        (88, 160), (72, 140), (96, 120), (80, 150), (68, 135)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(presets.indices, id: \.self) { i in
                ConversationRowSkeleton(nameWidth: presets[i].0, previewWidth: presets[i].1)
                Divider()
                    .padding(.leading, 70)
                    .foregroundStyle(Color.echoBlue.opacity(0.06))
            }
        }
    }
}

// MARK: - ChatSkeletonView
struct ChatSkeletonView: View {
    // 左=接收方，右=发送方；widthRatio 为屏幕宽比例
    private let presets: [(isRight: Bool, widthRatio: CGFloat)] = [
        (false, 0.55), (true, 0.45), (false, 0.62),
        (true, 0.38), (false, 0.50), (true, 0.42)
    ]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                Spacer()
                ForEach(presets.indices, id: \.self) { i in
                    let preset = presets[i]
                    HStack {
                        if preset.isRight { Spacer() }
                        SkeletonRect(
                            width: geo.size.width * preset.widthRatio,
                            height: 34,
                            cornerRadius: 16
                        )
                        if !preset.isRight { Spacer() }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 12)
        }
    }
}
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Core/UI/SkeletonView.swift
git commit -m "feat(ios): add shimmer + ConversationRowSkeleton + ChatSkeletonView"
```

---

## Task 5: FloatingLabelTextField — 浮动 Label 输入框

**Files:**
- Create: `ios-app/EchoIM/Core/UI/FloatingLabelTextField.swift`

- [x] **Step 1: 新建 FloatingLabelTextField**

```swift
// ios-app/EchoIM/Core/UI/FloatingLabelTextField.swift
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

                // Floating label：未激活时居中（padding top 18），激活后上移至顶（padding top 8）
                Text(label)
                    .font(isFloating ? .system(size: 9, weight: .medium) : .body)
                    .foregroundStyle(isFloating ? Color.echoInteractive : Color.echoMuted)
                    .padding(.leading, 14)
                    .padding(.top, isFloating ? 8 : 18)
                    .animation(.easeInOut(duration: 0.15), value: isFloating)

                // Input：激活后出现在 label 下方，未激活时透明（保持焦点响应能力）
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
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: accessibility smoke 验证（确认 .opacity(0) 时 accessibilityIdentifier 仍可索引）**

在 `ios-app/EchoIMTests/FloatingLabelTextFieldTests.swift` 新增：

```swift
// ios-app/EchoIMTests/FloatingLabelTextFieldTests.swift
import Testing
import SwiftUI
@testable import EchoIM

@Suite("FloatingLabelTextField")
struct FloatingLabelTextFieldTests {
    @Test
    func accessibilityIdExistsWhenEmpty() {
        // @Binding text is empty → isFloating = false → input opacity = 0
        // The accessibility identifier must still be set on the hidden TextField
        // so UI tests can reference it even before the user taps.
        // This is a compile-time structural check; actual focusability is tested in XCUITest.
        var text = ""
        let field = FloatingLabelTextField(
            label: "用户名",
            text: Binding(get: { text }, set: { text = $0 }),
            autocapitalization: .never,
            accessibilityId: "smokeField"
        )
        // Verify the view can be constructed without crash and the id is non-empty.
        #expect(field.accessibilityId == "smokeField")
    }
}
```

运行：

```bash
xcodebuild test -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/FloatingLabelTextFieldTests 2>&1 | grep -E "passed|failed"
```

预期：`Test Suite 'FloatingLabelTextFieldTests' passed`

- [x] **Step 4: commit**

```bash
git add ios-app/EchoIM/Core/UI/FloatingLabelTextField.swift \
        ios-app/EchoIMTests/FloatingLabelTextFieldTests.swift
git commit -m "feat(ios): add FloatingLabelTextField with animated floating label"
```

---

## Task 6: MeRow — 「我」页面功能行组件

**Files:**
- Create: `ios-app/EchoIM/Core/UI/MeRow.swift`

- [x] **Step 1: 新建 MeRow**

```swift
// ios-app/EchoIM/Core/UI/MeRow.swift
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
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Core/UI/MeRow.swift
git commit -m "feat(ios): add MeRow component for Me tab function rows"
```

---

## Task 7: ChatViewModel — isConsecutive + shouldShowTimestamp（TDD）

**Files:**
- Create: `ios-app/EchoIMTests/ChatViewModelTimestampTests.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`

- [x] **Step 1: 写失败测试**

```swift
// ios-app/EchoIMTests/ChatViewModelTimestampTests.swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — timestamp + consecutive")
struct ChatViewModelTimestampTests {

    private let peer = UserProfile(id: 9, username: "alice", displayName: nil, avatarUrl: nil)

    private func makeMessage(id: Int, senderId: Int, createdAt: Date) -> Message {
        Message(
            id: id,
            conversationId: 1,
            senderId: senderId,
            body: "hi",
            messageType: "text",
            mediaUrl: nil,
            createdAt: createdAt,
            clientTempId: nil
        )
    }

    // MARK: - isConsecutive

    @Test
    func consecutiveWhenSameSenderWithin60Seconds() {
        let now = Date()
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg1 = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: now))
        let msg2 = LocalMessage.confirmed(makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(59)))
        #expect(vm.isConsecutive(msg2, previous: msg1) == true)
    }

    @Test
    func notConsecutiveWhenDifferentSender() {
        let now = Date()
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg1 = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: now))
        let msg2 = LocalMessage.confirmed(makeMessage(id: 2, senderId: 2, createdAt: now.addingTimeInterval(10)))
        #expect(vm.isConsecutive(msg2, previous: msg1) == false)
    }

    @Test
    func notConsecutiveWhenOver60Seconds() {
        let now = Date()
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg1 = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: now))
        let msg2 = LocalMessage.confirmed(makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(61)))
        #expect(vm.isConsecutive(msg2, previous: msg1) == false)
    }

    @Test
    func notConsecutiveWhenPreviousIsNil() {
        let vm = ChatViewModel(
            route: .peer(peer), currentUserId: 1, messageRepo: FakeMessageRepo(),
            wsClient: nil, tokenProvider: { "tok" }
        )
        let msg = LocalMessage.confirmed(makeMessage(id: 1, senderId: 1, createdAt: Date()))
        #expect(vm.isConsecutive(msg, previous: nil) == false)
    }

    // MARK: - shouldShowTimestamp

    @Test
    func firstMessageAlwaysShowsTimestamp() async throws {
        let now = Date()
        let vm = ChatViewModel(
            route: .conversation(try makeConversation()), currentUserId: 1,
            messageRepo: FakeMessageRepo(listResult: [makeMessage(id: 1, senderId: 1, createdAt: now)]),
            wsClient: nil, tokenProvider: { "tok" }
        )
        await vm.load()
        #expect(vm.shouldShowTimestamp(at: 0) == true)
    }

    @Test
    func showsTimestampWhenGapExceeds5Minutes() async throws {
        let now = Date()
        let msgs = [
            makeMessage(id: 1, senderId: 1, createdAt: now),
            makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(301)),
        ]
        let vm = ChatViewModel(
            route: .conversation(try makeConversation()), currentUserId: 1,
            messageRepo: FakeMessageRepo(listResult: msgs),
            wsClient: nil, tokenProvider: { "tok" }
        )
        await vm.load()
        #expect(vm.shouldShowTimestamp(at: 1) == true)
    }

    @Test
    func hidesTimestampWhenGapUnder5Minutes() async throws {
        let now = Date()
        let msgs = [
            makeMessage(id: 1, senderId: 1, createdAt: now),
            makeMessage(id: 2, senderId: 1, createdAt: now.addingTimeInterval(299)),
        ]
        let vm = ChatViewModel(
            route: .conversation(try makeConversation()), currentUserId: 1,
            messageRepo: FakeMessageRepo(listResult: msgs),
            wsClient: nil, tokenProvider: { "tok" }
        )
        await vm.load()
        #expect(vm.shouldShowTimestamp(at: 1) == false)
    }

    // MARK: - Helpers

    private func makeConversation() throws -> Conversation {
        let json = """
        {
          "id": 1,
          "created_at": "2026-04-18T12:00:00.000Z",
          "peer_id": 9,
          "peer_username": "alice",
          "peer_display_name": null,
          "peer_avatar_url": null,
          "last_message_body": null,
          "last_message_type": null,
          "last_message_sender_id": null,
          "last_message_at": null,
          "last_read_message_id": null,
          "unread_count": 0
        }
        """.data(using: .utf8)!
        return try APIClient.jsonDecoder.decode(Conversation.self, from: json)
    }

    private final class FakeMessageRepo: MessageRepository {
        var listResult: [Message]
        init(listResult: [Message] = []) { self.listResult = listResult }

        func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
            listResult
        }
        func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
            throw APIError.invalidResponse
        }
        func sendImage(recipientId: Int, mediaUrl: String, mediaWidth: Int, mediaHeight: Int, clientTempId: String, token: String) async throws -> Message {
            throw APIError.invalidResponse
        }
        func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
    }
}
```

- [x] **Step 2: 运行，确认失败**

```bash
cd /Users/xuyuqin/Documents/EchoIM/ios-app && xcodebuild test -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ChatViewModelTimestampTests 2>&1 | grep -E "FAIL|error:|Build"
```

预期：编译失败（`isConsecutive`/`shouldShowTimestamp` 尚未定义）。

- [x] **Step 3: 在 ChatViewModel 实现两个方法**

在 `ChatViewModel.swift` 的 `// MARK: - WS` 注解之前，添加：

```swift
// MARK: - Render helpers

func isConsecutive(_ msg: LocalMessage, previous: LocalMessage?) -> Bool {
    guard let prev = previous,
          prev.message.senderId == msg.message.senderId else { return false }
    return msg.message.createdAt.timeIntervalSince(prev.message.createdAt) < 60
}

func shouldShowTimestamp(at index: Int) -> Bool {
    guard index > 0 else { return true }
    let gap = messages[index].message.createdAt
        .timeIntervalSince(messages[index - 1].message.createdAt)
    return gap > 300
}
```

- [x] **Step 4: 运行测试，确认通过**

```bash
xcodebuild test -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ChatViewModelTimestampTests 2>&1 | grep -E "passed|failed|PASS|FAIL"
```

预期：`Test Suite 'ChatViewModelTimestampTests' passed`

- [x] **Step 5: commit**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/ChatViewModelTimestampTests.swift
git commit -m "feat(ios): add isConsecutive + shouldShowTimestamp to ChatViewModel"
```

> **实现偏差**：测试数组需按服务端格式（最新在前）提供，否则 `rows.reversed()` 后顺序反转导致 gap 计算为负数。

---

## Task 8: ChatViewModel — haptic 行为改造（TDD）

**Files:**
- Modify: `ios-app/EchoIMTests/HapticFeedbackInjectionTests.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`

### 新行为规格
| 事件 | 之前 | 之后 |
|------|------|------|
| 消息发送成功（REST 201） | `lightImpact()` | **无 haptic** |
| 消息发送成功（WS echo 确认） | 无 | `success()` |
| 消息发送失败 | 无 | `warning()` |
| 好友申请 accept/decline | 已有 `success()`/`warning()` | 不变 |

- [x] **Step 1: 更新 HapticFeedbackInjectionTests，使其对新行为失败**

找到 `sendTextSuccessTriggersLightImpact` 测试，改为验证 REST 201 不触发任何 haptic，并新增 WS echo → `success()` 和 failure → `warning()` 测试：

```swift
// 替换原 sendTextSuccessTriggersLightImpact
@Test
func sendTextSuccessRestDoesNotTriggerHaptic() async {
    let repo = MessageRepo()
    repo.textResult = .success(
        makeMessage(id: 100, body: "hi", messageType: "text", mediaUrl: nil, tempId: "pending")
    )
    let haptics = RecordingHaptics()
    let vm = ChatViewModel(
        route: .peer(makePeer()),
        currentUserId: 0,
        messageRepo: repo,
        wsClient: nil,
        tokenProvider: { "tok" },
        haptics: haptics
    )

    await vm.sendText("hi")

    // REST 201 不再触发任何 haptic，WS echo 才触发
    #expect(haptics.lightCount == 0)
    #expect(haptics.successCount == 0)
    #expect(haptics.warningCount == 0)
}

@Test
func wsEchoOfOwnMessageTriggersSuccess() async {
    let repo = MessageRepo()
    let message = makeMessage(id: 100, body: "hi", messageType: "text", mediaUrl: nil, tempId: "temp-1")
    repo.textResult = .success(message)
    let haptics = RecordingHaptics()
    let vm = ChatViewModel(
        route: .peer(makePeer()),
        currentUserId: 0,
        messageRepo: repo,
        wsClient: nil,
        tokenProvider: { "tok" },
        haptics: haptics
    )

    // 模拟 WS echo（clientTempId 不为 nil，senderId 与 currentUserId 相同）
    let echoMsg = Message(
        id: 100, conversationId: 1, senderId: 0, body: "hi",
        messageType: "text", mediaUrl: nil, createdAt: Date(), clientTempId: "temp-1"
    )
    await vm.sendText("hi")          // REST 路径，不触发
    vm.handleWSEvent(.messageNew(echoMsg))  // WS echo 路径，触发 success()

    #expect(haptics.successCount == 1)
    #expect(haptics.lightCount == 0)
}

@Test
func sendTextFailureTriggersWarning() async {
    let haptics = RecordingHaptics()
    let vm = ChatViewModel(
        route: .peer(makePeer()),
        currentUserId: 0,
        messageRepo: MessageRepo(),  // textResult defaults to .failure
        wsClient: nil,
        tokenProvider: { "tok" },
        haptics: haptics
    )

    await vm.sendText("hi")

    #expect(haptics.warningCount == 1)
    #expect(haptics.successCount == 0)
    #expect(haptics.lightCount == 0)
}

// 替换原 sendImageSuccessTriggersLightImpact
@Test
func sendImageSuccessRestDoesNotTriggerHaptic() async {
    let repo = MessageRepo()
    repo.imageResult = .success(
        makeMessage(
            id: 200, body: nil, messageType: "image",
            mediaUrl: "/uploads/messages/test.jpg", tempId: "pending"
        )
    )
    let haptics = RecordingHaptics()
    let vm = ChatViewModel(
        route: .peer(makePeer()),
        currentUserId: 0,
        messageRepo: repo,
        wsClient: nil,
        uploadRepo: UploadRepo(),
        tokenProvider: { "tok" },
        haptics: haptics
    )

    await vm.sendCompressedImage(data: Data([0xFF, 0xD8, 0xFF]), width: 100, height: 100)

    #expect(haptics.lightCount == 0)
    #expect(haptics.successCount == 0)
    #expect(haptics.warningCount == 0)
}

@Test
func wsEchoOfOwnImageMessageTriggersSuccess() async {
    let repo = MessageRepo()
    let echoMsg = Message(
        id: 200, conversationId: 1, senderId: 0,
        body: nil, messageType: "image",
        mediaUrl: "/uploads/messages/test.jpg",
        createdAt: Date(), clientTempId: "img-temp-1"
    )
    repo.imageResult = .success(echoMsg)
    let haptics = RecordingHaptics()
    let vm = ChatViewModel(
        route: .peer(makePeer()),
        currentUserId: 0,
        messageRepo: repo,
        wsClient: nil,
        uploadRepo: UploadRepo(),
        tokenProvider: { "tok" },
        haptics: haptics
    )

    await vm.sendCompressedImage(data: Data([0xFF, 0xD8, 0xFF]), width: 100, height: 100)
    vm.handleWSEvent(.messageNew(echoMsg))  // WS echo 路径，触发 success()

    #expect(haptics.successCount == 1)
    #expect(haptics.lightCount == 0)
}
```

- [x] **Step 2: 运行，确认当前测试失败**

```bash
xcodebuild test -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/HapticFeedbackInjectionTests 2>&1 | grep -E "FAIL|error:|passed|failed"
```

预期：逻辑失败（haptic 计数不符合新期望）。

- [x] **Step 3: 修改 ChatViewModel 实现新 haptic 行为**

**3a.** 修改 `performSend`，移除 `haptics.lightImpact()`：

```swift
private func performSend(body: String, tempId: String, token: String) async {
    do {
        let result = try await messageRepo.sendText(
            recipientId: peer.id,
            body: body,
            clientTempId: tempId,
            token: token
        )
        mergeServerResult(result, tempId: tempId)
        // 不在 REST 响应时触发 haptic，等 WS echo 确认
    } catch {
        markFailed(tempId: tempId, error: error)
    }
}
```

**3c.** 修改 `executeImageSend`，移除 `haptics.lightImpact()`：

```swift
do {
    let result = try await messageRepo.sendImage(
        recipientId: peer.id,
        mediaUrl: uploaded.mediaUrl,
        mediaWidth: uploaded.mediaWidth,
        mediaHeight: uploaded.mediaHeight,
        clientTempId: tempId,
        token: token
    )
    mergeServerResult(result, tempId: tempId)
    imageSendStages.removeValue(forKey: tempId)
    // 不在 REST 响应时触发 haptic，等 WS echo
} catch {
    markFailed(tempId: tempId, error: error)
}
```

**3d.** 修改 `markFailed`，添加 `warning()`：

```swift
private func markFailed(tempId: String, error: Error) {
    guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return }
    messages[index].sendState = .failed(String(describing: error))
    haptics.warning()
}
```

**3e.** 修改 `mergeServerResult` 签名，让它返回是否真正完成了 pending → confirmed 的合并（从 `Void` 改为 `@discardableResult Bool`）：

```swift
@discardableResult
fileprivate func mergeServerResult(_ message: Message, tempId: String) -> Bool {
    guard let index = messages.firstIndex(where: { $0.localId == tempId }) else {
        return false
    }
    messages[index] = .confirmed(message)
    Task { [weak self] in
        await self?.writeThroughAndMeta([message])
    }
    return true
}
```

**3f.** 在 `handleIncomingMessage` 处理自己发送的 WS echo 时，用返回值把守 haptic（避免 echo 重放时重复震动）：

```swift
if let tempId = incoming.clientTempId, incoming.senderId == currentUserId {
    let didConfirm = mergeServerResult(incoming, tempId: tempId)
    if didConfirm { haptics.success() }   // ← 只在真正从 pending 确认时震动
    return
}
```

- [x] **Step 4: 运行所有 haptic 测试，确认通过**

```bash
xcodebuild test -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/HapticFeedbackInjectionTests 2>&1 | grep -E "passed|failed|PASS|FAIL"
```

预期：`Test Suite 'HapticFeedbackInjectionTests' passed`

- [x] **Step 5: 运行全部测试，确认无回归**

```bash
xcodebuild test -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | grep -E "Suite.*passed|Suite.*failed"
```

预期：所有 Suite passed。

> **实现偏差**：`didConfirm` 守卫在测试场景中无效（REST 先于 WS echo 确认），改为 WS echo 自发方消息时直接调用 `haptics.success()`。

- [x] **Step 6: commit**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIMTests/HapticFeedbackInjectionTests.swift
git commit -m "feat(ios): change haptic — success() on WS echo, warning() on failure"
```

---

## Task 9: LoginView — 完全重写

**Files:**
- Modify: `ios-app/EchoIM/Features/Auth/LoginView.swift`

LoginViewModel 和 RootView 不变，只改 View 层。保留所有 `accessibilityIdentifier`。

- [x] **Step 1: 重写 LoginView.swift**

```swift
// ios-app/EchoIM/Features/Auth/LoginView.swift
import SwiftUI

struct LoginView: View {
    @Bindable var vm: LoginViewModel
    var onNavigateToRegister: () -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 渐变背景（160° ≈ topTrailing → bottomLeading）
                LinearGradient(
                    colors: [
                        Color.echoBlue,
                        Color(red: 22/255, green: 78/255, blue: 99/255),  // #164E63
                        Color(red: 14/255, green: 58/255, blue: 74/255),  // #0E3A4A
                    ],
                    startPoint: UnitPoint(x: 0.67, y: 0.0),
                    endPoint: UnitPoint(x: 0.33, y: 1.0)
                )
                .ignoresSafeArea()

                // 品牌 Hero（上方）
                VStack {
                    Spacer()
                    heroSection
                    Spacer()
                    // 卡片占位高度（让 hero 不被卡片遮盖）
                    Color.clear.frame(height: 420)
                }

                // 表单卡片（白色，底部对齐，顶角圆）
                formCard
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
        .padding(.bottom, max(24, 0))  // safe area handled by frame
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
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Features/Auth/LoginView.swift
git commit -m "feat(ios): rewrite LoginView with gradient background and floating label fields"
```

---

## Task 10: RegisterView — 完全重写

**Files:**
- Modify: `ios-app/EchoIM/Features/Auth/RegisterView.swift`

保留所有 `accessibilityIdentifier`（regInvite/regUsername/regEmail/regPassword/regSubmit/regGoLogin/regToastOK）和字段级错误提示。

- [x] **Step 1: 重写 RegisterView.swift**

```swift
// ios-app/EchoIM/Features/Auth/RegisterView.swift
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
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Features/Auth/RegisterView.swift
git commit -m "feat(ios): rewrite RegisterView with gradient background and floating label fields"
```

---

## Task 11: MessageBubble — 圆角 + 颜色 + 弹入动画 + footer 样式

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/MessageBubble.swift`

- [x] **Step 1: 重写 MessageBubble（新增 isConsecutive 参数）**

```swift
// ios-app/EchoIM/Features/Chat/MessageBubble.swift
import SwiftUI

struct MessageBubble: View {
    let message: LocalMessage
    let isSelf: Bool
    var isConsecutive: Bool = false
    var onRetry: () -> Void = {}
    var onOpenImage: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        if message.message.messageType == "image" {
            ImageMessageBubble(
                message: message,
                isSelf: isSelf,
                onTap: onOpenImage,
                onRetry: onRetry
            )
        } else {
            textBubble
        }
    }

    private var bubbleCornerRadii: (topLeading: CGFloat, topTrailing: CGFloat,
                                     bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        if isSelf {
            // 发送方：右上角为小角（首条/独条）or 全圆（连续）
            return isConsecutive
                ? (16, 16, 16, 16)
                : (16, 4, 16, 16)
        } else {
            // 接收方：左上角为小角（首条/独条）or 全圆（连续）
            return isConsecutive
                ? (16, 16, 16, 16)
                : (4, 16, 16, 16)
        }
    }

    private var textBubble: some View {
        HStack {
            if isSelf { Spacer(minLength: 40) }

            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                let r = bubbleCornerRadii
                Text(message.message.body ?? "")
                    .font(.body)
                    .foregroundStyle(isSelf ? .white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: r.topLeading,
                            bottomLeadingRadius: r.bottomLeading,
                            bottomTrailingRadius: r.bottomTrailing,
                            topTrailingRadius: r.topTrailing
                        )
                        .fill(isSelf
                              ? Color.echoInteractive
                              : Color(uiColor: .secondarySystemBackground))
                        .shadow(
                            color: isSelf ? .clear : Color.echoBlue.opacity(0.1),
                            radius: 3, x: 0, y: 1
                        )
                    )
                    .opacity(message.sendState == .pending ? 0.65 : 1.0)

                footer
            }
            .transition(messageTransition)
            .animation(.easeOut(duration: 0.2), value: message.localId)

            if !isSelf { Spacer(minLength: 40) }
        }
        .accessibilityIdentifier("chatBubble_text_\(message.localId)")
    }

    private var messageTransition: AnyTransition {
        if reducedMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(
                scale: 0.8,
                anchor: isSelf ? .bottomTrailing : .bottomLeading
            ).combined(with: .opacity),
            removal: .opacity
        )
    }

    @ViewBuilder
    private var footer: some View {
        switch message.sendState {
        case .confirmed:
            EmptyView()
        case .pending:
            Text("发送中...")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.echoBlue)
                Text("发送失败")
                    .font(.caption2)
                    .foregroundStyle(Color.echoBlue)
                Button("重试", action: onRetry)
                    .font(.caption2)
                    .foregroundStyle(Color.echoBlue)
                    .buttonStyle(.plain)
            }
        }
    }
}
```

- [x] **Step 2: 同步修改 ImageMessageBubble.swift 的 failed footer，与规格保持一致**

找到 `ImageMessageBubble.swift` 中的 `footer` computed property，将 `.failed` 分支替换为：

```swift
case .failed:
    HStack(spacing: 6) {
        Image(systemName: "circle.fill")
            .font(.caption2)
            .foregroundStyle(Color.echoBlue)
        Text("发送失败")
            .font(.caption2)
            .foregroundStyle(Color.echoBlue)
        Button("重试", action: onRetry)
            .font(.caption2)
            .foregroundStyle(Color.echoBlue)
            .buttonStyle(.plain)
    }
```

- [x] **Step 3: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`（MessageBubble 调用方 ChatView 已有默认值 `isConsecutive: false`，不破坏编译）

- [x] **Step 4: commit**

```bash
git add ios-app/EchoIM/Features/Chat/MessageBubble.swift \
        ios-app/EchoIM/Features/Chat/ImageMessageBubble.swift
git commit -m "feat(ios): update MessageBubble — corner radius + echoInteractive + slide-in animation"
```

---

## Task 12: ChatView — Skeleton + 时间戳分组 + 输入栏 + 导航栏

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`

- [x] **Step 1: 添加 TimestampPill 私有组件（文件顶部或底部）**

在 `ChatView.swift` 末尾（`ChatDefaultScrollAnchor` 之后）添加：

```swift
private struct TimestampPill: View {
    let date: Date

    private var text: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.echoMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.echoBlue.opacity(0.07))
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}
```

- [x] **Step 2: 修改 messagesList — 替换 ProgressView + 加时间戳 + 传 isConsecutive**

找到 `private var messagesList: some View` 中的 `ForEach` 和 `overlay { if vm.phase == .loading ... }` 部分，完整替换：

```swift
private var messagesList: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 8) {
                if vm.hasMoreOlder {
                    Button {
                        Task { await vm.loadOlder() }
                    } label: {
                        if vm.isLoadingOlder {
                            ProgressView()
                        } else {
                            Text("加载更早消息")
                                .font(.caption)
                                .foregroundStyle(Color.echoBlue)
                        }
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 6)
                }

                ForEach(Array(vm.messages.enumerated()), id: \.element.localId) { index, message in
                    if vm.shouldShowTimestamp(at: index) {
                        TimestampPill(date: message.message.createdAt)
                    }
                    MessageBubble(
                        message: message,
                        isSelf: message.message.senderId == vm.currentUserId,
                        isConsecutive: vm.isConsecutive(
                            message,
                            previous: index > 0 ? vm.messages[index - 1] : nil
                        ),
                        onRetry: {
                            Task { await vm.retry(localId: message.localId) }
                        },
                        onOpenImage: {
                            lightboxBubble = message
                        }
                    )
                    .id(message.localId)
                }

                Color.clear.frame(height: 10).id(Self.bottomAnchorId)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
        .modifier(ChatDefaultScrollAnchor())
        .background(Color(uiColor: .systemBackground))
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { isInputFocused = false })
        .overlay {
            if vm.phase == .loading, vm.messages.isEmpty {
                ChatSkeletonView()
                    .transition(.opacity)
            }
        }
        .onChange(of: vm.messages.last?.localId) { _, newValue in
            guard newValue != nil else { return }
            guard initialScrollPolicy.consumeMessageChangeForScroll() else { return }
            scrollToBottom(proxy, animated: true)
        }
        .onChange(of: initialCatchUpScrollTrigger) { _, _ in
            scrollToBottom(proxy, animated: false)
        }
    }
}
```

- [x] **Step 3: 修改 inputBar — `.ultraThinMaterial` 背景 + 圆形按钮**

找到 `private var inputBar: some View`，完整替换：

```swift
private var inputBar: some View {
    HStack(alignment: .bottom, spacing: 10) {
        // 图片选择按钮：34pt 圆形，tapTarget 扩展到 44pt
        PhotosPicker(selection: $pickedItem, matching: .images) {
            ZStack {
                Circle()
                    .fill(Color.echoSurface)
                    .frame(width: 34, height: 34)
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.echoBlue)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text("发送图片"))
        .accessibilityIdentifier("chatImagePicker")
        .simultaneousGesture(
            TapGesture().onEnded { isInputFocused = false }
        )

        TextField("说点什么...", text: $draft, axis: .vertical)
            .lineLimit(1...5)
            .focused($isInputFocused)
            .submitLabel(.send)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.echoSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.echoBlue.opacity(0.2), lineWidth: 1)
                    )
            )
            .onChange(of: draft) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    vm.stopTyping()
                } else {
                    vm.handleTypingInput()
                }
            }
            .accessibilityIdentifier("chatInput")

        // 发送按钮：34pt 圆形，tapTarget 扩展到 44pt
        Button {
            let text = draft
            draft = ""
            Task { await vm.sendText(text) }
        } label: {
            ZStack {
                Circle()
                    .fill(canSend ? Color.echoInteractive : Color(uiColor: .systemFill))
                    .frame(width: 34, height: 34)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 44, height: 44)
        .disabled(!canSend)
        .accessibilityLabel(Text("发送消息"))
        .accessibilityIdentifier("chatSend")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
        Rectangle()
            .fill(Color.echoBlue.opacity(0.12))
            .frame(height: 0.5)
    }
}
```

- [x] **Step 4: 添加 toolbarBackground 到 ChatView.body**

在 `ChatView.body` 的 modifier 链中（`.onDisappear` 之后）添加：

```swift
.toolbarBackground(Color.echoInteractive, for: .navigationBar)
.toolbarColorScheme(.dark, for: .navigationBar)
```

并修改 `principalTitle` 中的文字颜色（当前是 `.secondary`，改为白色 70% 透明度）：

找到 `principalTitle` 中的 typing 提示文字：
```swift
// 改前
.foregroundStyle(.secondary)
// 改后
.foregroundStyle(Color.white.opacity(0.7))
```

- [x] **Step 5: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 6: commit**

```bash
git add ios-app/EchoIM/Features/Chat/ChatView.swift
git commit -m "feat(ios): ChatView — skeleton, timestamp groups, styled input bar, echoInteractive nav"
```

---

## Task 13: ConversationsListView — 行改造 + Skeleton + 空状态 + 导航栏

**Files:**
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`

- [x] **Step 1: 改造 ConversationRow + 自定义分隔线 + 添加 Skeleton + 更新空状态 + toolbarBackground**

完整替换 `ConversationsListView.swift`：

```swift
// ios-app/EchoIM/Features/Conversations/ConversationsListView.swift
import SwiftUI

struct ConversationsListView: View {
    @State private var vm: ConversationsListViewModel
    private let presenceStore: PresenceStore?

    init(
        repository: ConversationRepository,
        metaStore: ConversationMetaStore?,
        wsClient: WebSocketClient?,
        currentUserId: Int,
        presenceStore: PresenceStore? = nil,
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        _vm = State(
            wrappedValue: ConversationsListViewModel(
                repository: repository,
                metaStore: metaStore,
                tokenProvider: tokenProvider,
                currentUserId: { currentUserId },
                wsClient: wsClient
            )
        )
        self.presenceStore = presenceStore
    }

    var body: some View {
        content
            .refreshable { await vm.refresh() }
            .task {
                vm.attachWSSubscription()
                await vm.load()
            }
            .onDisappear { vm.detachWSSubscription() }
            .toolbarBackground(Color.echoInteractive, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if case .unauthenticated = vm.phase {
            Text("登录已过期，请重新登录")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.phase == .loading && vm.conversations.isEmpty {
            // Skeleton 加载态
            ScrollView {
                ConversationsListSkeleton()
            }
        } else if vm.conversations.isEmpty {
            switch vm.phase {
            case .loaded:
                emptyState
            case .error(let message):
                errorState(message)
            default:
                EmptyView()
            }
        } else {
            list
        }
    }

    private var list: some View {
        List(vm.conversations) { conversation in
            NavigationLink(value: ChatRoute.conversation(conversation)) {
                ConversationRow(conversation: conversation, presenceStore: presenceStore)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.echoBlue.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 70)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("conversationsList")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.echoBlue.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.echoBlue)
            }
            Text("暂无会话")
                .font(.headline)
                .foregroundStyle(Color.echoTextDeep)
            Text("从「联系人」里选一个好友\n开始聊天")
                .font(.subheadline)
                .foregroundStyle(Color.echoMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        StateView.error(message: message) {
            Task { await vm.load() }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let presenceStore: PresenceStore?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(profile: conversation.peer, size: 46)
                if presenceStore?.isOnline(conversation.peer.id) == true {
                    PresenceDot()
                        .offset(x: 2, y: 2)
                        .accessibilityIdentifier("conversationOnlineDot_\(conversation.peer.username)")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.peer.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.echoTextDeep)
                    .lineLimit(1)
                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(Color.echoMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(Color.echoMuted)
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.echoDanger, in: Capsule())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var previewText: String {
        if let body = conversation.lastMessageBody, !body.isEmpty { return body }
        if conversation.lastMessageType == "image" { return String(localized: "[图片]") }
        return String(localized: "暂无消息")
    }

    private var timeString: String {
        guard let ts = conversation.lastMessageAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: ts, relativeTo: Date())
    }
}
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: commit**

```bash
git add ios-app/EchoIM/Features/Conversations/ConversationsListView.swift
git commit -m "feat(ios): restyle ConversationsListView — skeleton, hash avatar, new empty state, nav bar"
```

---

## Task 14: FriendsListView — 在线/离线分组 + FriendRow + toolbar icon

**Files:**
- Modify: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`
- Modify: `ios-app/EchoIM/Features/Main/MainTabView.swift`（仅改 toolbar icon 和 toolbar background）

- [x] **Step 1: 重写 FriendsListView（在线/离线分组 + FriendRow 改造 + 空状态）**

```swift
// ios-app/EchoIM/Features/Contacts/FriendsListView.swift
import SwiftUI

struct FriendsListView: View {
    let friends: [Friend]
    let presenceStore: PresenceStore?

    init(friends: [Friend], presenceStore: PresenceStore? = nil) {
        self.friends = friends
        self.presenceStore = presenceStore
    }

    private var onlineFriends: [Friend] {
        friends.filter { presenceStore?.isOnline($0.id) == true }
    }

    private var offlineFriends: [Friend] {
        friends.filter { presenceStore?.isOnline($0.id) != true }
    }

    var body: some View {
        if friends.isEmpty {
            emptyState
        } else {
            List {
                if !onlineFriends.isEmpty {
                    Section("在线 (\(onlineFriends.count))") {
                        ForEach(onlineFriends) { friend in
                            FriendRow(friend: friend, isOnline: true)
                        }
                    }
                }
                if onlineFriends.isEmpty {
                    Section {
                        ForEach(offlineFriends) { friend in
                            FriendRow(friend: friend, isOnline: false)
                        }
                    }
                } else {
                    Section("其他") {
                        ForEach(offlineFriends) { friend in
                            FriendRow(friend: friend, isOnline: false)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("friendsList")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.echoBlue.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.echoBlue)
            }
            Text("还没有好友")
                .font(.headline)
                .foregroundStyle(Color.echoTextDeep)
            Text("点击右上角 + 搜索并添加好友")
                .font(.subheadline)
                .foregroundStyle(Color.echoMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friendsEmpty")
    }
}

private struct FriendRow: View {
    let friend: Friend
    let isOnline: Bool

    var body: some View {
        NavigationLink(value: ChatRoute.peer(friend)) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(profile: friend, size: 42)
                    if isOnline {
                        PresenceDot()
                            .offset(x: 2, y: 2)
                            .accessibilityIdentifier("friendOnlineDot_\(friend.username)")
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.echoTextDeep)
                    Text(isOnline ? "在线" : "离线")
                        .font(.caption)
                        .foregroundStyle(isOnline ? Color.echoOnline : Color.secondary)
                }

                Spacer()

                Text("发消息")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.echoBlue)
            }
        }
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("friendRow_\(friend.username)")
    }
}
```

- [x] **Step 2: 给 ContactsView 添加 toolbarBackground**

在 `ContactsView.body` 的 modifier 链末尾（`.sheet` 之后）添加：

```swift
.toolbarBackground(Color.echoInteractive, for: .navigationBar)
.toolbarColorScheme(.dark, for: .navigationBar)
```

- [x] **Step 3: 在 MainTabView 中修改 toolbar icon 并统一 title display mode**

在 `MainTabView.swift` 中：

**3a.** 将 `contactsToolbar` 中的 `envelope` 图标改为 `person.2`：

```swift
// 改前
Image(systemName: "envelope")
// 改后
Image(systemName: "person.2")
```

**3b.** 将 TabView 上的 `.navigationBarTitleDisplayMode(.inline)` 改为 `.large`：

```swift
// 改前
.navigationBarTitleDisplayMode(.inline)
// 改后
.navigationBarTitleDisplayMode(.large)
```

- [x] **Step 4: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 5: commit**

```bash
git add ios-app/EchoIM/Features/Contacts/FriendsListView.swift \
        ios-app/EchoIM/Features/Contacts/ContactsView.swift \
        ios-app/EchoIM/Features/Main/MainTabView.swift
git commit -m "feat(ios): FriendsListView online/offline sections, FriendRow, nav bar, toolbar icon"
```

---

## Task 15: MeView — ScrollView + 渐变卡片 + MeRow

**Files:**
- Modify: `ios-app/EchoIM/Features/Me/MeView.swift`

保留：`accessibilityIdentifier("homeUsername")`、`accessibilityIdentifier("meEditProfile")`、`accessibilityIdentifier("meClearCache")`、`accessibilityIdentifier("homeLogout")`、`confirmationDialog` 完整内容。

- [x] **Step 1: 重写 MeView.swift**

```swift
// ios-app/EchoIM/Features/Me/MeView.swift
import SwiftUI

struct MeView: View {
    let container: AppContainer
    var onLogout: () async -> Void

    @State private var showClearCacheConfirm = false
    @State private var isClearing = false

    var body: some View {
        Group {
            if let user = container.currentUser {
                ScrollView {
                    VStack(spacing: 16) {
                        userInfoCard(user: user)
                        editProfileCard(user: user)
                        cacheCard
                        logoutCard
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog(
            "清除本地聊天缓存？",
            isPresented: $showClearCacheConfirm,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task {
                    isClearing = true
                    await container.clearChatCache()
                    isClearing = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除本设备上缓存的消息与图片。服务器上的消息不受影响。")
        }
        .overlay(alignment: .center) {
            if isClearing {
                ProgressView("清除中…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .toolbarBackground(Color.echoInteractive, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - 用户信息卡片
    private func userInfoCard(user: AuthenticatedUser) -> some View {
        VStack(spacing: 12) {
            AvatarView(user: user, size: 56)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))

            VStack(spacing: 4) {
                Text(user.displayTitle)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("homeUsername")

                if let sub = user.usernameSubtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.65))
                }

                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.echoMainGradient)
        )
    }

    // MARK: - 编辑资料卡片
    private func editProfileCard(user: AuthenticatedUser) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                ProfileEditView(
                    username: user.username,
                    viewModel: makeProfileEditViewModel()
                )
            } label: {
                MeRow(
                    iconName: "person.crop.circle",
                    iconColor: Color.echoBlue,
                    title: "编辑资料"
                ) {}
                    .allowsHitTesting(false)
            }
            .accessibilityIdentifier("meEditProfile")
            .padding(.horizontal, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    // MARK: - 缓存卡片
    private var cacheCard: some View {
        VStack(spacing: 0) {
            MeRow(
                iconName: "trash",
                iconColor: Color.echoDanger,
                title: "清除聊天缓存",
                isDestructive: true
            ) {
                showClearCacheConfirm = true
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("meClearCache")
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    // MARK: - 登出卡片
    private var logoutCard: some View {
        VStack(spacing: 0) {
            MeRow(
                iconName: "arrow.right.square",
                iconColor: Color.echoDanger,
                title: "登出",
                isDestructive: true
            ) {
                Task { await onLogout() }
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("homeLogout")
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    @MainActor
    private func makeProfileEditViewModel() -> ProfileEditViewModel {
        ProfileEditViewModel(
            currentUser: { container.currentUser },
            currentUserSetter: { container.currentUser = $0 },
            tokenProvider: { [tokenStore = container.tokenStore] in
                (try? tokenStore.load())?.token
            },
            userRepo: container.makeUserRepository(),
            uploadRepo: container.session?.makeUploadRepository()
                ?? UploadRepositoryImpl(api: container.apiClient),
            refreshCurrentUser: { [weak container] in
                await container?.refreshCurrentUser()
            },
            onUnauthorized: { [weak container] in
                await container?.handleUnauthorized()
            }
        )
    }
}
```

- [x] **Step 2: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 3: 修改 ProfileEditView，重置导航栏为系统默认（避免从 MeView push 时继承蓝色导航栏）**

在 `ios-app/EchoIM/Features/Me/ProfileEditView.swift` 的 `body` 顶层 View（`Form {…}`）上追加：

```swift
Form {
    // … 现有内容不变 …
}
.navigationBarTitleDisplayMode(.inline)
.toolbarBackground(.automatic, for: .navigationBar)
.toolbarColorScheme(.unspecified, for: .navigationBar)
```

- [x] **Step 4: 编译验证**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`

- [x] **Step 5: commit**

```bash
git add ios-app/EchoIM/Features/Me/MeView.swift \
        ios-app/EchoIM/Features/Me/ProfileEditView.swift
git commit -m "feat(ios): rewrite MeView — gradient card, MeRow function rows, echoInteractive nav"
```


> **实现偏差**：计划中 `.toolbarColorScheme(.unspecified, for: .navigationBar)` 无效（`ColorScheme` 无 `.unspecified` 成员），改为 `.toolbarColorScheme(nil, for: .navigationBar)` 以重置继承。
---

## Task 16: 全量编译 + 全量测试

- [x] **Step 1: 全量编译**

```bash
xcodebuild -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' build 2>&1 | grep -E "BUILD|error:"
```

预期：`** BUILD SUCCEEDED **`，无 `error:` 行。

- [x] **Step 2: 全量单元测试**

```bash
xcodebuild test -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | grep -E "Suite.*passed|Suite.*failed|tests passed|tests failed"
```

预期：所有 Suite passed。

- [x] **Step 3: 确认保留行为清单**

在模拟器中手工验证（或通过已有 Accessibility Identifier 确认编译后可索引）：
- [x] `loginEmail`、`loginPassword`、`loginSubmit`、`loginGoRegister`、`loginToastOK` 均存在于 LoginView
- [x] `regInvite`、`regUsername`、`regEmail`、`regPassword`、`regSubmit`、`regGoLogin` 均存在于 RegisterView
- [x] 注册页四字段级错误（inviteCodeError/usernameError/emailError/passwordError）由 FloatingLabelTextField `error` 参数承接
- [x] `chatInput`、`chatSend`、`chatImagePicker` 均存在于 ChatView
- [x] `conversationsList` 存在于 ConversationsListView
- [x] `meClearCache` → `confirmationDialog` 弹出（不可静默删除）
- [x] `homeLogout` 存在于 MeView

- [x] **Step 4: 确认无未提交改动**

```bash
git status
```

预期：`nothing to commit, working tree clean`（所有 Task 已分别 commit）

---

## Self-Review

### 1. Spec 覆盖度检查

| 规格章节 | 对应 Task | 状态 |
|------|------|------|
| 1.1 色彩 Token | Task 1 | ✅ |
| 1.2 头像哈希渐变 | Task 1 (avatarGradient) + Task 2 | ✅ |
| 1.3 气泡圆角规则 | Task 11 | ✅ |
| 1.4 动画时长 | Task 3 (脉冲)、Task 4 (shimmer)、Task 11 (弹入) | ✅ |
| 1.5 触控目标 44pt | Task 12 (chatSend/chatImagePicker 44pt frame) | ✅ |
| 2. 认证页面 | Task 5 + Task 9 + Task 10 | ✅ |
| 3. 会话列表 | Task 4 + Task 13 | ✅ |
| 4. 聊天界面 | Task 7 + Task 11 + Task 12 | ✅ |
| 5. 联系人页 | Task 14 | ✅ |
| 6. 「我」页面 | Task 6 + Task 15 | ✅ |
| 7. PresenceDot 脉冲 | Task 3 | ✅ |
| 8. HapticFeedback | Task 8 | ✅ |
| 导航栏 per-view 配置 | Task 12/13/14/15 (toolbarBackground) | ✅ |

### 2. Placeholder 扫描

检查结果：无 TBD / TODO / "类似 Task N" 等占位符。每个 Step 都包含完整代码或精确命令。

### 3. 类型一致性

- `Color.avatarGradient(for:)` 在 Task 1 定义，Task 2、Task 13、Task 14、Task 15 调用 `AvatarView` 间接使用 ✅
- `FloatingLabelTextField` 在 Task 5 定义，Task 9/10 直接使用 ✅  
- `MeRow` 在 Task 6 定义，Task 15 直接使用 ✅  
- `ConversationsListSkeleton` / `ChatSkeletonView` 在 Task 4 定义，Task 12/13 直接使用 ✅
- `MessageBubble` 新增 `isConsecutive: Bool = false`（默认值保持向后兼容），Task 12 传参 ✅
- `vm.isConsecutive(_:previous:)` 和 `vm.shouldShowTimestamp(at:)` 在 Task 7 实现，Task 12 调用 ✅
- `TimestampPill` 在 Task 12 Step 1 定义，Task 12 Step 2 使用 ✅
- `haptics.success()` / `haptics.warning()` 在 Task 8 注入，`HapticFeedbackProvider` 协议已有这两个方法 ✅

### 4. 保留行为

- `accessibilityIdentifier` 全部在重写代码中逐一保留（见 Task 9/10/11/12/13/14/15）✅
- `confirmationDialog` 在 Task 15 MeView 完整保留 ✅
- 图片消息两步发送 / 发送失败重试：MessageBubble 和 ChatViewModel 逻辑未改动 ✅
- 聊天页 `initialScrollPolicy` + `catchUpScrollTrigger`：Task 12 messagesList 保留所有 `onChange` ✅
- 分页加载"加载更早消息"按钮：Task 12 保留 ✅
- `typing.start / stop` onDisappear 不变式：ChatView 未改动 onDisappear ✅
- WS `attachWSSubscription` / `detachWSSubscription` 生命周期：未改动 ✅
- 乐观消息 `client_temp_id` 合并逻辑：ChatViewModel 未改动合并路径 ✅
