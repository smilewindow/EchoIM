# EchoIM iOS UI 重设计 — 设计规格

**日期：** 2026-05-03  
**范围：** 全量精细化（方案三）——登录/注册、会话列表、聊天界面、联系人、「我」页面 + Skeleton 加载态 + 动画  
**技术栈：** SwiftUI + iOS 17+

---

## 1. 设计系统

### 1.1 色彩 Token

| Token | 值 | 用途 |
|---|---|---|
| `echoBlue` | `#0891B2` | 渐变起点、气泡背景（无白字直接叠加） |
| `echoInteractive` | `#0E7490` | 按钮、导航栏背景（白字对比度 5.2:1，达 WCAG AA） |
| `echoCyan` | `#22D3EE` | 渐变终点、高亮 |
| `echoSurface` | `#ECFEFF` | 页面背景、输入框底色 |
| `echoTextDeep` | `#164E63` | 标题、主文字 |
| `echoMuted` | `#337C8A` | 副文字、时间戳（在 echoSurface 上对比度 4.6:1，达 WCAG AA） |
| `echoOnline` | `#34C759` | 在线状态点（= iOS 系统绿） |
| `echoDanger` | `#FF3B30` | 未读角标、发送失败（= iOS 系统红） |

> **对比度说明：**  
> - 白字 on `echoInteractive #0E7490`：5.2:1 ✅ WCAG AA  
> - `echoMuted #337C8A` on `echoSurface #ECFEFF`：4.6:1 ✅ WCAG AA  
> - `echoTextDeep #164E63` on `echoSurface #ECFEFF`：8.76:1 ✅ WCAG AAA  

**主渐变：** `LinearGradient(colors: [.echoBlue, .echoCyan], startPoint: .topLeading, endPoint: .bottomTrailing)`  
**按钮/导航栏渐变：** `LinearGradient(colors: [.echoInteractive, .echoBlue], startPoint: .topLeading, endPoint: .bottomTrailing)`

**深色模式：** 自定义颜色通过 `Color(light:dark:)` 扩展提供深色变体；系统色（`.systemBackground`、`.secondarySystemBackground` 等）自动适配，无需额外处理。

| Token | 亮色 | 暗色 |
|---|---|---|
| `echoBlue` | `#0891B2` | `#0891B2` |
| `echoInteractive` | `#0E7490` | `#0E7490` |
| `echoCyan` | `#22D3EE` | `#22D3EE` |
| `echoSurface` | `#ECFEFF` | `#0C1A1F`（深青黑） |
| `echoTextDeep` | `#164E63` | `#A5F3FC` |
| `echoMuted` | `#337C8A` | `#5BA3B0` |

### 1.2 头像渐变色（哈希着色）

对 `username` 做简单哈希，映射到 8 套渐变之一，保证同一用户颜色始终一致：

| index | 渐变 |
|---|---|
| 0 | `#0891B2 → #22D3EE`（青蓝） |
| 1 | `#7C3AED → #A78BFA`（紫） |
| 2 | `#E11D48 → #FB7185`（玫瑰） |
| 3 | `#D97706 → #FCD34D`（琥珀） |
| 4 | `#059669 → #34D399`（绿） |
| 5 | `#0EA5E9 → #7DD3FC`（天蓝） |
| 6 | `#DC2626 → #F87171`（红） |
| 7 | `#7C3AED → #C4B5FD`（淡紫） |

实现：`username.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 8`

### 1.3 圆角规则

| 场景 | 值 |
|---|---|
| 发送气泡（首条/独条） | `16 4 16 16`（右上小角） |
| 发送气泡（连续） | `16 16 16 16` |
| 接收气泡（首条/独条） | `4 16 16 16`（左上小角） |
| 接收气泡（连续） | `16 16 16 16` |
| 输入框字段 | `12` |
| 登录白色卡片 | `24 24 0 0` |
| 「我」页面卡片 | `14` |
| 功能行容器 | `14` |

**「连续」判定：** 同一发送方、相邻消息时间差 < 60 秒。

### 1.4 动画时长

| 场景 | 时长 | 曲线 |
|---|---|---|
| 消息弹入 | 200ms | `.easeOut` |
| 按钮按下缩放 | 150ms | `.easeInOut` |
| 在线点脉冲（循环） | 2000ms | `.easeInOut(duration: 1).repeatForever` |
| Skeleton shimmer（循环） | 1400ms | `.linear.repeatForever` |

遵守 `@Environment(\.accessibilityReduceMotion)`：为 `true` 时跳过弹入和脉冲动画。

### 1.5 触控目标

所有可点击元素最小 **44×44 pt**（UI/UX Pro Max CRITICAL 规范）。具体：发送按钮 44pt 圆形、图片选择按钮 44pt、导航栏图标按钮用 `.frame(width:44, height:44)` 包裹。

---

## 2. 认证页面（LoginView / RegisterView）

### 布局结构

```
NavigationStack（无可见导航栏）
└── ZStack
    ├── 渐变背景全屏（echoBlue → #164E63 → #0E3A4A，160°）
    ├── 品牌 Hero 区（居中，flex 占满上方空间）
    │   ├── Logo 方块（56pt，cornerRadius 16，白色半透明背景）
    │   ├── "EchoIM"（.largeTitle.bold，白色）
    │   └── 副标题（"Real-time messaging"，白色 55% 透明度）
    └── 表单卡片（白色，cornerRadius 24 24 0 0，从底部弹出）
        ├── 标题（"欢迎回来" / "创建账号"，.title3.bold）
        ├── 字段组（FloatingLabelTextField × 2/3）
        ├── 主按钮（"登录" / "注册"，echoInteractive 背景，cornerRadius 12，高度 50pt）
        └── 跳转链接（"没有账号？立即注册"）
```

### FloatingLabelTextField 组件

自定义组件，替换当前的 `TextField` + `Section` 方案：

- 背景：`echoSurface`，边框 `echoBlue 20% 透明度`，`cornerRadius 12`
- 聚焦时边框变为 `echoInteractive 100%`，动画 150ms
- Label 在未输入时居中显示（占位符行为），有内容后缩小到字段顶部（9pt，echoInteractive 颜色）
- 高度：56pt（满足 44pt 触控要求并留有视觉呼吸空间）
- **必须透传：** `textContentType`、`keyboardType`、`textInputAutocapitalization`、`autocorrectionDisabled`、`.accessibilityIdentifier`
- **字段级错误：** 若传入非 nil 的 `error: String?`，在字段下方以 `.footnote` 红色显示，与现有 RegisterView 行为一致

```swift
struct FloatingLabelTextField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var error: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var accessibilityId: String? = nil
    // ...
}
```

### 注册页字段清单

注册页有 **4 个字段**（LoginView 有 2 个），重写时必须全部保留：

| 字段 | accessibilityIdentifier | textContentType | 备注 |
|---|---|---|---|
| 邀请码 | `regInvite` | — | autocap .never |
| 用户名 | `regUsername` | — | autocap .never |
| 邮箱 | `regEmail` | `.emailAddress` | keyboard .emailAddress |
| 密码 | `regPassword` | `.newPassword` | SecureField |

登录页 accessibilityIdentifiers：`loginEmail`、`loginPassword`、`loginSubmit`、`loginGoRegister`、`loginToastOK`。

### 错误处理

- 字段级错误（RegisterView 现有）：保留，由 FloatingLabelTextField 的 `error` 参数承接
- 全局错误 `.alert` 弹窗：保留，样式不变

---

## 3. 会话列表（ConversationsListView）

### ConversationRow 改动

| 属性 | 当前 | 新 |
|---|---|---|
| 头像尺寸 | 44pt | 46pt |
| 头像背景 | `.secondarySystemBackground` 灰 | 哈希渐变（1.2节） |
| 名字字体 | `.subheadline.semibold` | 保持不变 |
| 预览字体 | `.caption` | 保持不变 |
| 行内边距 | `top/bottom 2` | `top/bottom 6` |
| 分隔线 | `.hidden` | 保持 hidden，改用自定义细线 `0.5pt，echoBlue 6%` |

### 加载态

- 初次加载（`vm.phase == .loading && vm.conversations.isEmpty`）：显示 5 行 `ConversationRowSkeleton`
- `ConversationRowSkeleton`：圆形头像骨架（46pt）+ 两行文字骨架，宽度使用**固定 preset**（不随机，避免 SwiftUI body 重算时抖动）：

```swift
// 5 行固定 preset（名字宽 / 预览宽）
private let skeletonPresets: [(CGFloat, CGFloat)] = [
    (88, 160), (72, 140), (96, 120), (80, 150), (68, 135)
]
```

### 空状态

替换现有 `StateView.empty`：
- 图标：`bubble.left.and.bubble.right`（系统图标，48pt，echoBlue 10% 背景圆）
- 标题：`echoTextDeep`，`.headline`
- 提示：`echoMuted`，`.subheadline`，两行居中

### 导航栏

- `.navigationBarTitleDisplayMode(.large)`（当前 `.inline`）
- 颜色：**per-view** 方式，不使用全局 `UINavigationBarAppearance`（会污染 sheet 和详情页）：

```swift
// 在各 tab 根视图 + ChatView 加：
.toolbarBackground(Color.echoInteractive, for: .navigationBar)
.toolbarColorScheme(.dark, for: .navigationBar)
```

各页面导航栏颜色规格：

| 页面 | 导航栏背景 | title mode |
|---|---|---|
| 会话列表 | `echoInteractive` 蓝 | `.large` |
| 联系人 | `echoInteractive` 蓝 | `.large` |
| 「我」 | `echoInteractive` 蓝 | `.large` |
| 聊天页 | `echoInteractive` 蓝 | `.inline` |
| ProfileEditView | 系统默认 | `.inline` |
| UserDetailView | 系统默认 | `.inline` |
| FriendRequestsSheetView | 系统默认（sheet 自带） | `.inline` |
| UserSearchSheetView | 系统默认（sheet 自带） | `.inline` |

---

## 4. 聊天界面（ChatView / MessageBubble）

### 4.1 导航栏

```
ToolbarItem(.principal)
├── AvatarView（28pt，哈希渐变）
├── 名字（.body.semibold，白色）
├── PresenceDot（8pt 绿色）       ← 在线时
└── "正在输入…"（.caption2，白色 70%）  ← 打字时（替换名字下方副标题）
```

### 4.2 MessageBubble

**文字气泡新增逻辑：**

```swift
// 连续消息判定（ChatViewModel 或 render 层）
func isConsecutive(_ msg: LocalMessage, previous: LocalMessage?) -> Bool {
    guard let prev = previous,
          prev.message.senderId == msg.message.senderId else { return false }
    return msg.message.createdAt.timeIntervalSince(prev.message.createdAt) < 60
}
```

气泡圆角根据 `isSelf` + `isConsecutive` 组合选取（见 1.3 节）。

**接收方气泡：**
- 背景：`Color(uiColor: .secondarySystemBackground)`（深色模式自动适配）
- 增加 `shadow(color: .echoBlue.opacity(0.1), radius: 3, x: 0, y: 1)`

**发送方气泡：**
- 背景：`echoInteractive`（白字对比度 5.2:1，echoBlue 3.68:1 不达标）
- 无阴影

**Pending 状态：** 保持 `opacity(0.65)` + "发送中…" caption，不变。

**Failed 状态：** 将现有感叹号图标改为 `circle.fill` 红色实心，`"发送失败"` + `"重试"` 颜色改为 `echoBlue`。

**发送弹入动画：**

```swift
// MessageBubble
.transition(.asymmetric(
    insertion: .scale(scale: 0.8, anchor: isSelf ? .bottomTrailing : .bottomLeading)
        .combined(with: .opacity),
    removal: .opacity
))
.animation(.easeOut(duration: 0.2), value: message.localId)
```

遵守 `reducedMotion`：为 `true` 时 insertion 只用 `.opacity`。

### 4.3 时间戳分组

在 `ChatViewModel` 或渲染层计算 `shouldShowTimestamp(at index:) -> Bool`：

```swift
// 首条消息，或与上一条消息相差 > 5 分钟时显示时间戳
func shouldShowTimestamp(at index: Int) -> Bool {
    guard index > 0 else { return true }
    let gap = messages[index].message.createdAt
        .timeIntervalSince(messages[index - 1].message.createdAt)
    return gap > 300
}
```

时间戳样式：居中 pill，背景 `echoBlue 7% 透明度`，字体 `.caption2`，颜色 `echoMuted`。

### 4.4 Skeleton 加载态

进入会话时（`vm.phase == .loading && vm.messages.isEmpty`）显示 `ChatSkeletonView`：

- 6 个骨架气泡，使用**固定 preset**（位置和宽度写死，避免 body 重算抖动）：

```swift
// 左=接收方，右=发送方；宽度为屏幕宽比例
private let chatSkeletonPresets: [(isRight: Bool, widthRatio: CGFloat)] = [
    (false, 0.55), (true, 0.45), (false, 0.62),
    (true, 0.38), (false, 0.50), (true, 0.42)
]
```

- 高度 34pt，shimmer 动画，数据到达后 `.opacity` 淡出，消息列表淡入

### 4.5 输入栏

```
HStack
├── 图片选择按钮（34pt 圆形，echoSurface + echoBlue 图标，tapTarget 包裹至 44pt）
├── TextField（圆角 18，echoSurface 背景，echoBlue 20% 边框）
└── 发送按钮（34pt 圆形，echoInteractive，tapTarget 44pt）
```

背景：`.ultraThinMaterial`，顶部边框 `echoBlue 12% 透明度`。

---

## 5. 联系人页（FriendsListView）

### 列表结构

将原来的平铺列表改为分组展示：

```
Section "在线 (N)"   ← 仅在有在线好友时显示
  FriendRow（有绿点）
Section "其他"
  FriendRow（无绿点）
```

### FriendRow

- 头像：42pt，哈希渐变
- 在线状态文字：在线显示 `"在线"（.caption，echoOnline）`；离线显示 `"离线"（.caption，.secondary）`（UserProfile 无 lastSeenAt，不展示具体时间）
- 右侧：`"发消息"` 文字按钮（`.caption，echoBlue，font-weight .semibold`）→ push 到对应会话

### 好友申请角标

将现有 `ToolbarItem(.topBarLeading)` 的 `Image(systemName: "envelope")` 替换为 `Image(systemName: "person.2")`，角标样式保持不变（红色 Capsule）。

### 空状态

无好友时显示：图标 `person.badge.plus` + "还没有好友" + "点击右上角 + 搜索并添加好友"。

---

## 6. 「我」页面（MeView）

### 布局结构

移除 `Form`，改为 `ScrollView` + 手动布局：

```
ScrollView
├── 用户信息卡片（LinearGradient echoBlue→echoCyan，cornerRadius 14，margin 12）
│   ├── AvatarView（56pt，哈希渐变，白色边框 2.5pt）
│   ├── displayTitle（.title3.bold，白色）
│   ├── @username（.subheadline，白色 65%）
│   └── email（.caption，白色 50%）
├── 功能组卡片 1（白色，cornerRadius 14，margin 12 横向）
│   └── 编辑资料行（彩色图标 + 标题 + "›" chevron）
├── 功能组卡片 2
│   └── 清除聊天缓存行
└── 功能组卡片 3
    └── 登出行（红色文字，红色图标）
```

### MeRow 组件

```swift
struct MeRow: View {
    let iconName: String
    let iconColor: Color
    let title: String
    var isDestructive: Bool = false
    var action: () -> Void
}
```

图标：28pt 圆角方形背景（对应浅色），SF Symbol 14pt。

---

## 7. 在线状态点（PresenceDot）

在现有 `PresenceDot` 基础上添加脉冲波纹：

```swift
ZStack {
    Circle()
        .fill(Color.echoOnline.opacity(isAnimating ? 0 : 0.4))
        .frame(width: size * 2, height: size * 2)
        .scaleEffect(isAnimating ? 1.8 : 1.0)
    Circle()
        .fill(Color.echoOnline)
        .frame(width: size, height: size)
}
.onAppear {
    guard !reducedMotion else { return }
    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
        isAnimating = true
    }
}
```

波纹仅在 `size >= 9`（会话列表/联系人场景）时显示；聊天导航栏（8pt）不显示波纹。

---

## 8. 触觉反馈（HapticFeedback.swift 沿用）

现有协议方法：`lightImpact()`、`success()`、`warning()`（见 `HapticFeedback.swift`）。

| 事件 | 调用方法 | 触发时机 |
|---|---|---|
| 消息发送成功 | `success()` | `sendState` 变为 `.confirmed`（WS echo），**不在 REST 响应时触发**，避免双触发 |
| 消息发送失败 | `warning()` | `sendState` 变为 `.failed` |
| 好友申请接受 | `success()` | 操作完成回调（与现有测试 `successCount == 1` 一致） |
| 好友申请拒绝 | `warning()` | 操作完成回调（与现有测试 `warningCount == 1` 一致） |
| 发送按钮按下（已有） | 保持不变 | 保持不变 |

---

## 9. 实现范围与文件影响

| 文件 | 改动性质 |
|---|---|
| `Assets.xcassets` | 新增 `EchoColors`（echoBlue、echoCyan 等 Color Set） |
| `Core/UI/AvatarView.swift` | 改造 initialsPlaceholder → 哈希渐变 |
| `Core/UI/PresenceDot.swift` | 添加脉冲波纹动画 |
| `Core/UI/SkeletonView.swift` | 新建：ConversationRowSkeleton、ChatSkeletonView |
| `Core/UI/FloatingLabelTextField.swift` | 新建 |
| `Core/UI/MeRow.swift` | 新建 |
| `Core/Extensions/Color+Echo.swift` | 新建：定义所有 Token（含 echoInteractive）+ 深色变体 |
| `Features/Auth/LoginView.swift` | 完全重写（移除 Form，换自定义布局） |
| `Features/Auth/RegisterView.swift` | 完全重写（与 LoginView 共用品牌顶部） |
| `Features/Conversations/ConversationsListView.swift` | ConversationRow 头像/间距改造 + Skeleton |
| `Features/Chat/ChatView.swift` | 导航栏 + 输入栏 + Skeleton |
| `Features/Chat/MessageBubble.swift` | 圆角规则 + 阴影 + 弹入动画 + footer 样式 |
| `Features/Chat/ChatViewModel.swift` | 新增 `shouldShowTimestamp` + `isConsecutive` |
| `Features/Contacts/FriendsListView.swift` | 在线/离线分组 + FriendRow 改造 |
| `Features/Me/MeView.swift` | 移除 Form，换 ScrollView + 卡片布局 |
| `Features/Main/MainTabView.swift` | NavigationBar appearance 配置 |

---

## 10. 必须保留的现有行为

视觉重构不得破坏以下行为，实现时需逐一验证：

| 行为 | 所在文件 |
|---|---|
| 所有 `accessibilityIdentifier`（loginEmail/loginPassword/loginSubmit/loginGoRegister/loginToastOK/regInvite/regUsername/regEmail/regPassword/regSubmit/regGoLogin/chatInput/chatSend/chatImagePicker/conversationsList 等） | Auth/Chat/Conversations views |
| 注册页四字段级错误提示（inviteCodeError/usernameError/emailError/passwordError） | RegisterView + RegisterViewModel |
| 清缓存 confirmationDialog（不可静默删除） | MeView |
| 图片消息两步发送 + 发送失败重试 | ChatViewModel + ImageMessageBubble |
| 聊天页初始滚动到底部（含 catchUp scroll trigger） | ChatView |
| 分页加载更早消息（"加载更早消息"按钮） | ChatView + ChatViewModel |
| typing start/stop 不变式（onDisappear 时强制 stop） | ChatView |
| WS 订阅的 attach/detach 生命周期 | ConversationsListView / ChatView |
| 乐观消息 `client_temp_id` 合并逻辑 | ChatViewModel |

## 11. 不在本次范围内

- 群聊功能
- 深色模式独立颜色微调（系统色自动适配已覆盖大部分场景）
- iPad 适配
- 通知横幅 UI
- 启动屏（Launch Screen）品牌化
