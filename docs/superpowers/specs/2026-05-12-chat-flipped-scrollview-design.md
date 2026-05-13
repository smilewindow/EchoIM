# 聊天消息列表翻转 ScrollView 设计

## 背景与问题

ChatView 的消息列表当前使用 `ScrollView` + `VStack`（非 Lazy），配合 `ScrollViewReader.scrollTo` 实现首次进入滚底和新消息滚底。选择 VStack 而非 LazyVStack 的原因是 SwiftUI 的经典坑：`LazyVStack` + `ScrollViewReader.scrollTo` + 动态高度内容在滚底时容易算错锚点。

但 VStack 会一次性实例化所有消息视图，消息数量增长后将成为性能瓶颈。

### 约束

- 首次进入聊天页面时必须自动处于最新消息位置（底部）
- 键盘弹出时，消息列表 + 输入栏作为整体上移到键盘上方（当前通过 `.ignoresSafeArea(.keyboard)` + `offset(y: -keyboardHeight)` 实现）
- iOS 17+ deployment target
- 不破坏现有 ChatViewModel 的数据结构和测试

## 方案选型

### 方案 1（采用）：翻转 ScrollView（Flipped Layout）

将 ScrollView 旋转 180°，每个 cell 再旋转 180° 翻回来，数据数组倒序显示。"底部"变成 ScrollView 的自然起始位置，无需 `scrollTo` 即可定位到最新消息。

这是业界聊天 UI 的标准做法（Telegram、微信、iMessage、WhatsApp 均基于 UIKit 翻转 TableView/CollectionView 的同一原理）。

**优点：**
- 可安全使用 LazyVStack，因为不再依赖 scrollTo 跳到列表末尾
- 首次进入天然在底部，无需 ChatInitialScrollPolicy
- 键盘避让不受影响（翻转在 ScrollView 内部，外层 offset 不变）

**代价：**
- 原生滚动指示器方向反转，需隐藏并自定义
- "加载更早消息"按钮在 ForEach 中的位置从头部移到尾部
- 视图层需要 reversedMessages computed property

### 方案 2（不采用）：`defaultScrollAnchor(.bottom)` + LazyVStack

iOS 17 新增 API，只控制初始锚定位置。新消息到达时仍需 `scrollTo`，没有解决根本问题。

### 方案 3（不采用）：UIKit UICollectionView 桥接

最强大但复杂度远超作品集项目需要。

## 详细设计

### 1. 翻转布局核心

```
ScrollView                    ← .scaleEffect(x: 1, y: -1)
  LazyVStack(spacing: 8)      ← 内容容器
    ForEach(reversedMessages)
      Cell                    ← .scaleEffect(x: 1, y: -1)  // 每个 cell 翻回正向
```

用 `.scaleEffect(x: 1, y: -1)` 而非 `.rotationEffect(.degrees(180))`，避免影响水平方向手势判定。

**数据源：** ChatView 上加 computed property `reversedMessages`，对 `vm.messages` 做 `.reversed()`。VM 的 `messages` 数组保持原有时间正序不变，翻转只是视图层的事。

**ForEach id：** 继续用 `.id(message.localId)`，不变。

### 2. 自定义滚动指示器

隐藏原生指示器（`.scrollIndicators(.hidden)`），用 overlay 叠加自定义竖条：

- 在 ScrollView 内用 GeometryReader 感知 content offset 和 content 总高度
- 在外层用 overlay 绘制右侧竖条
- 翻转后 offset 方向相反，需做 `1 - normalizedOffset` 映射
- 仅在滚动时淡入、停止后延迟淡出，模拟系统行为

### 3. 新消息滚底行为

#### 首次进入

翻转布局天然处于底部（ScrollView 起始位置），不需要任何 scrollTo。

删除 `ChatInitialScrollPolicy` 整套机制。

#### "是否在底部"的持续追踪

在每次滚动变化时（GeometryReader 回调），持续更新 `isNearBottom` 布尔状态：

- 阈值：固定 ~60pt（约一条文本消息的高度）
- 翻转后 offset ≈ 0 表示在视觉底部，`offset < 60` 即为 `isNearBottom = true`
- 持续追踪的好处：新消息插入可能导致 offset 跳变，但判定用的是插入前已缓存的状态，不受影响
- 这与主流 IM 应用（Telegram、微信等）的做法一致：UIKit 下用 20~50pt 固定阈值

#### 新消息到达时

- **`isNearBottom == true`：** 做一次轻量 `scrollTo(reversedMessages.first.id, anchor: .top)`。滚动距离仅一条消息高度，不会触发 LazyVStack 动态高度测量问题。
- **`isNearBottom == false`：** 不自动滚动，显示 "↓ N 条新消息" 浮动按钮，点击后滚到底部。N 的计算方式：ChatView 维护一个 `newMessagesSinceScrollAway` 计数器，当 `isNearBottom` 从 true 变为 false 时重置为 0，之后每收到一条非自己发送的新消息 +1。用户滚回底部或点击按钮后重置。

#### 用户自己发送消息

无论 `isNearBottom` 状态如何，一律滚到底部。

### 4. "加载更早消息"按钮

翻转后数据倒序，最早的消息在 reversedMessages 数组末尾。

- 按钮从 ForEach 头部移到尾部（视觉上仍在顶部，因为翻转了）
- 按钮本身也需要 `.scaleEffect(x: 1, y: -1)` 翻回正向
- 触发逻辑（`vm.loadOlder()`）不变
- VM 的 `messages.insert(at: 0)` 不需要修改，视图层 reversedMessages 自动将旧消息放到正确位置

### 5. 键盘避让

外层结构完全不变：

```
VStack(spacing: 0) {          // 不变
    messagesList              // 内部 ScrollView 翻转
    inputBar                  // 不变
}
.offset(y: -keyboardHeight)   // 不变
```

`ChatKeyboardAvoidance` 的所有逻辑不需要修改。翻转是 ScrollView 内部的事，不影响外层的整体偏移。

## 代码变更清单

### 删除

- `ChatInitialScrollPolicy.swift` 整个文件
- `ChatView` 中的 `initialScrollPolicy` 和 `initialCatchUpScrollTrigger` 状态
- `onChange(of: initialCatchUpScrollTrigger)` 监听
- `onChange(of: vm.messages.last?.localId)` 自动滚底逻辑
- 底部锚点 `bottomAnchorId`

### 修改

- `ChatView.messagesList`：ScrollView + VStack → 翻转 ScrollView + LazyVStack + reversed 数据 + cell 翻转
- `scrollToBottom()`：改为滚到 reversed 数组第一个元素（anchor 改为 `.top`）
- "加载更早消息"按钮：从 ForEach 头部移到尾部

### 新增

- `reversedMessages` computed property（ChatView 视图层）
- 自定义滚动指示器组件（overlay + GeometryReader）
- `isNearBottom` 持续追踪状态（~60pt 阈值）
- "↓ N 条新消息" 浮动按钮

### 不需要改动

- `ChatViewModel`——messages 数组保持时间正序，翻转只是视图层的事
- `ChatKeyboardAvoidance`——外层结构不变
- `MessageBubble` / `ImageMessageBubble`——气泡本身不变
- 所有 ViewModel 测试——不涉及视图层翻转
