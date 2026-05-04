# EchoIM iOS UI 重设计 — 设计规格

**日期：** 2026-05-03  
**范围：** 全量精细化（方案三）——登录/注册、会话列表、聊天界面、联系人、「我」页面 + Skeleton 加载态 + 动画  
**技术栈：** SwiftUI + iOS 17+

---

## 1. 设计系统

### 1.1 色彩 Token

| Token | 值 | 用途 |
|---|---|---|
| `echoBlue` | `#0891B2` | 主色：发送气泡、按钮、导航栏、渐变起点 |
| `echoCyan` | `#22D3EE` | 辅助：渐变终点、高亮 |
| `echoSurface` | `#ECFEFF` | 页面背景、输入框底色 |
| `echoTextDeep` | `#164E63` | 标题、主文字 |
| `echoMuted` | `#64B5C4` | 副文字、时间戳 |
| `echoOnline` | `#34C759` | 在线状态点（= iOS 系统绿） |
| `echoDanger` | `#FF3B30` | 未读角标、发送失败（= iOS 系统红） |

**主渐变：** `LinearGradient(colors: [.echoBlue, .echoCyan], startPoint: .topLeading, endPoint: .bottomTrailing)`

**深色模式：** 自定义颜色通过 `Color(light:dark:)` 扩展提供深色变体；系统色（`.systemBackground`、`.secondarySystemBackground` 等）自动适配，无需额外处理。

| Token | 亮色 | 暗色 |
|---|---|---|
| `echoBlue` | `#0891B2` | `#0891B2`（保持不变） |
| `echoCyan` | `#22D3EE` | `#22D3EE`（保持不变） |
| `echoSurface` | `#ECFEFF` | `#0C1A1F`（深青黑） |
| `echoTextDeep` | `#164E63` | `#A5F3FC` |
| `echoMuted` | `#64B5C4` | `#4B9CAD` |

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
        ├── 主按钮（"登录" / "注册"，echoBlue 背景，cornerRadius 12，高度 50pt）
        └── 跳转链接（"没有账号？立即注册"）
```

### FloatingLabelTextField 组件

自定义组件，替换当前的 `TextField` + `Section` 方案：

- 背景：`echoSurface`，边框 `echoBlue 20% 透明度`，`cornerRadius 12`
- 聚焦时边框变为 `echoBlue 100%`，动画 150ms
- Label 在未输入时居中显示（占位符行为），有内容后缩小到字段顶部（9pt，echoBlue 颜色）
- 高度：56pt（满足 44pt 触控要求并留有视觉呼吸空间）

### 错误处理

保留现有 `.alert` 弹窗逻辑，样式不变。

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
- `ConversationRowSkeleton`：圆形头像骨架（46pt）+ 两行文字骨架（宽度随机 60-80pt / 100-140pt），shimmer 动画

### 空状态

替换现有 `StateView.empty`：
- 图标：`bubble.left.and.bubble.right`（系统图标，48pt，echoBlue 10% 背景圆）
- 标题：`echoTextDeep`，`.headline`
- 提示：`echoMuted`，`.subheadline`，两行居中

### 导航栏

- `.navigationBarTitleDisplayMode(.large)`（当前 `.inline`）
- 颜色：通过 `UINavigationBarAppearance` 设置背景为 `echoBlue`，前景白色

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
- 背景：`echoBlue`
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

- 6 个骨架气泡，左右随机分布，宽度 40-70%，高度 34pt
- shimmer 动画，数据到达后 `.opacity` 淡出，消息列表淡入

### 4.5 输入栏

```
HStack
├── 图片选择按钮（34pt 圆形，echoSurface + echoBlue 图标，tapTarget 包裹至 44pt）
├── TextField（圆角 18，echoSurface 背景，echoBlue 20% 边框）
└── 发送按钮（34pt 圆形，echoBlue，tapTarget 44pt）
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
- 在线状态文字：在线显示 `"在线"（.caption，echoOnline）`；离线显示 `"X 小时前在线"（.caption，.secondary）`
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

| 事件 | 反馈 |
|---|---|
| 消息发送成功（WS confirmed） | `.soft` |
| 消息发送失败 | `.error` |
| 好友申请接受/拒绝 | `.medium` |
| 发送按钮按下（已有） | 保持不变 |

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
| `Core/Extensions/Color+Echo.swift` | 新建：定义所有 Token + 深色变体 |
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

## 10. 不在本次范围内

- 群聊功能
- 深色模式独立颜色微调（系统色自动适配已覆盖大部分场景）
- iPad 适配
- 通知横幅 UI
- 启动屏（Launch Screen）品牌化
