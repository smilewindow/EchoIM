# 聊天消息列表翻转 ScrollView 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 ChatView 的消息列表从 VStack 改为翻转 LazyVStack，解决大量消息时的性能问题，同时保持首次进入滚底、键盘避让等现有行为。

**Architecture:** 翻转 ScrollView（`.scaleEffect(x: 1, y: -1)`）+ 每个 cell 反向翻转。数据源用 `reversedMessages` computed property 倒序渲染，VM 的 `messages` 数组保持时间正序不变。自定义滚动指示器替代被翻转的原生指示器。持续追踪 `isNearBottom` 状态来控制新消息自动滚底。

**Tech Stack:** SwiftUI, Swift Testing, iOS 17+

**Spec:** `docs/superpowers/specs/2026-05-12-chat-flipped-scrollview-design.md`

---

## 文件结构

### 新建

| 文件 | 职责 |
|------|------|
| `EchoIM/Features/Chat/ChatScrollState.swift` | 纯值类型，追踪 `isNearBottom` 和 `newMessageCount` |
| `EchoIM/Features/Chat/ChatScrollIndicator.swift` | 自定义滚动指示器视图 + `ScrollIndicatorMetrics` 计算逻辑 |
| `EchoIMTests/ChatScrollStateTests.swift` | ChatScrollState 单元测试 |
| `EchoIMTests/ChatScrollIndicatorTests.swift` | ScrollIndicatorMetrics 计算逻辑单元测试 |

### 修改

| 文件 | 变更 |
|------|------|
| `EchoIM/Features/Chat/ChatView.swift` | messagesList 翻转改造、scrollToBottom 更新、集成新组件、删除旧滚动逻辑 |

### 删除

| 文件 | 原因 |
|------|------|
| `EchoIM/Features/Chat/ChatInitialScrollPolicy.swift` | 翻转布局天然在底部，不再需要 |
| `EchoIMTests/ChatInitialScrollPolicyTests.swift` | 对应实现已删除 |

---

## Task 1: ChatScrollState

纯值类型，追踪滚动位置是否在底部附近，以及用户离开底部后收到的新消息数量。

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/ChatScrollState.swift`
- Test: `ios-app/EchoIMTests/ChatScrollStateTests.swift`

- [ ] **Step 1: 编写测试**

```swift
// ios-app/EchoIMTests/ChatScrollStateTests.swift
import Testing
@testable import EchoIM

@Suite("ChatScrollState")
struct ChatScrollStateTests {
    @Test func initialState_isNearBottom() {
        let state = ChatScrollState()
        #expect(state.isNearBottom)
        #expect(state.newMessageCount == 0)
    }

    @Test func offsetBelowThreshold_staysNearBottom() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(30)
        #expect(state.isNearBottom)
    }

    @Test func offsetAboveThreshold_leavesBottom() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        #expect(!state.isNearBottom)
    }

    @Test func incomingMessage_whenNotNearBottom_increments() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 1)
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 2)
    }

    @Test func incomingMessage_whenNearBottom_doesNotIncrement() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(30)
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 0)
    }

    @Test func scrollBackToBottom_resetsCount() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessage()
        state.recordIncomingMessage()
        #expect(state.newMessageCount == 2)
        state.updateOffset(30)
        #expect(state.isNearBottom)
        #expect(state.newMessageCount == 0)
    }

    @Test func reset_clearsCount() {
        var state = ChatScrollState(threshold: 60)
        state.updateOffset(100)
        state.recordIncomingMessage()
        state.reset()
        #expect(state.newMessageCount == 0)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ChatScrollStateTests 2>&1 | tail -20`

Expected: 编译失败，`ChatScrollState` 未定义。

- [ ] **Step 3: 编写实现**

```swift
// ios-app/EchoIM/Features/Chat/ChatScrollState.swift
struct ChatScrollState {
    private(set) var isNearBottom: Bool = true
    private(set) var newMessageCount: Int = 0

    let threshold: CGFloat

    init(threshold: CGFloat = 60) {
        self.threshold = threshold
    }

    mutating func updateOffset(_ offset: CGFloat) {
        let wasNearBottom = isNearBottom
        isNearBottom = offset < threshold
        if isNearBottom, !wasNearBottom {
            newMessageCount = 0
        }
    }

    mutating func recordIncomingMessage() {
        guard !isNearBottom else { return }
        newMessageCount += 1
    }

    mutating func reset() {
        newMessageCount = 0
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ChatScrollStateTests 2>&1 | tail -20`

Expected: 7 tests passed.

- [ ] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatScrollState.swift ios-app/EchoIMTests/ChatScrollStateTests.swift
git commit -m "feat(ios): add ChatScrollState for scroll position tracking"
```

---

## Task 2: ScrollIndicatorMetrics + ChatScrollIndicator

滚动指示器的位置计算逻辑（可测试的纯值类型）和 SwiftUI 视图。同时定义两个 PreferenceKey 供 ChatView 追踪 scroll offset 和 content height。

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/ChatScrollIndicator.swift`
- Test: `ios-app/EchoIMTests/ChatScrollIndicatorTests.swift`

- [ ] **Step 1: 编写 ScrollIndicatorMetrics 测试**

```swift
// ios-app/EchoIMTests/ChatScrollIndicatorTests.swift
import Testing
@testable import EchoIM

@Suite("ScrollIndicatorMetrics")
struct ChatScrollIndicatorTests {
    @Test func contentFitsViewport_shouldNotShow() {
        let m = ScrollIndicatorMetrics(contentHeight: 500, viewportHeight: 800, offset: 0)
        #expect(!m.shouldShow)
    }

    @Test func contentExceedsViewport_shouldShow() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 0)
        #expect(m.shouldShow)
    }

    @Test func indicatorHeight_proportionalToViewport() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 0)
        // 800/2000 * 800 = 320, which is > minHeight(30)
        #expect(m.indicatorHeight == 320)
    }

    @Test func indicatorHeight_respectsMinimum() {
        let m = ScrollIndicatorMetrics(contentHeight: 50000, viewportHeight: 800, offset: 0)
        // 800/50000 * 800 = 12.8, below min 30
        #expect(m.indicatorHeight == 30)
    }

    @Test func offsetZero_indicatorAtBottom() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 0)
        // normalized=0 → indicatorTop = (1-0)*(800-320) = 480
        #expect(m.indicatorTop == 480)
    }

    @Test func offsetMax_indicatorAtTop() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 1200)
        // maxOffset=1200, normalized=1 → indicatorTop = 0
        #expect(m.indicatorTop == 0)
    }

    @Test func offsetHalf_indicatorAtMiddle() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 600)
        // normalized=0.5 → indicatorTop = 0.5 * 480 = 240
        #expect(m.indicatorTop == 240)
    }

    @Test func offsetClamped_neverNegative() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: -50)
        #expect(m.indicatorTop >= 0)
        #expect(m.indicatorTop <= 800)
    }

    @Test func offsetClamped_neverExceedsTrack() {
        let m = ScrollIndicatorMetrics(contentHeight: 2000, viewportHeight: 800, offset: 9999)
        #expect(m.indicatorTop == 0)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ChatScrollIndicatorTests 2>&1 | tail -20`

Expected: 编译失败，`ScrollIndicatorMetrics` 未定义。

- [ ] **Step 3: 编写 ScrollIndicatorMetrics + PreferenceKeys + ChatScrollIndicator 视图**

```swift
// ios-app/EchoIM/Features/Chat/ChatScrollIndicator.swift
import SwiftUI

// MARK: - Preference Keys

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Metrics

struct ScrollIndicatorMetrics {
    let indicatorHeight: CGFloat
    let indicatorTop: CGFloat
    let shouldShow: Bool

    private static let minHeight: CGFloat = 30

    init(contentHeight: CGFloat, viewportHeight: CGFloat, offset: CGFloat) {
        guard contentHeight > viewportHeight else {
            shouldShow = false
            indicatorHeight = 0
            indicatorTop = 0
            return
        }

        shouldShow = true
        indicatorHeight = max(
            viewportHeight / contentHeight * viewportHeight,
            Self.minHeight
        )

        let maxOffset = contentHeight - viewportHeight
        let normalized = maxOffset > 0
            ? min(max(offset / maxOffset, 0), 1)
            : 0
        indicatorTop = (1 - normalized) * (viewportHeight - indicatorHeight)
    }
}

// MARK: - View

struct ChatScrollIndicator: View {
    let metrics: ScrollIndicatorMetrics
    let isVisible: Bool

    private let indicatorWidth: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: indicatorWidth / 2)
            .fill(Color.primary.opacity(0.3))
            .frame(width: indicatorWidth, height: metrics.indicatorHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(y: metrics.indicatorTop)
            .padding(.trailing, 2)
            .opacity(metrics.shouldShow && isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: isVisible)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ChatScrollIndicatorTests 2>&1 | tail -20`

Expected: 9 tests passed.

- [ ] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatScrollIndicator.swift ios-app/EchoIMTests/ChatScrollIndicatorTests.swift
git commit -m "feat(ios): add ChatScrollIndicator with metrics calculation"
```

---

## Task 3: 重构 ChatView.messagesList 为翻转布局

核心改造：将 ScrollView + VStack 替换为翻转 ScrollView + LazyVStack，集成 ChatScrollState、ChatScrollIndicator、新消息浮动按钮。同时删除旧的滚底逻辑。

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`

### Step 3.1: 添加新的状态属性，删除旧状态

- [ ] **Step 1: 替换状态属性**

在 `ChatView` 中：

删除以下属性：
```swift
@State private var initialScrollPolicy = ChatInitialScrollPolicy()
@State private var initialCatchUpScrollTrigger = 0
```

替换为：
```swift
@State private var scrollState = ChatScrollState()
@State private var scrollOffset: CGFloat = 0
@State private var scrollContentHeight: CGFloat = 0
@State private var viewportHeight: CGFloat = 0
@State private var isScrolling = false
@State private var scrollIdleTimer: Task<Void, Never>?
```

删除顶部的静态常量：
```swift
private static let bottomAnchorId = "chatBottomAnchor"
```

- [ ] **Step 2: 添加 reversedMessages computed property**

在 ChatView 中添加：
```swift
private var reversedMessages: [LocalMessage] {
    Array(vm.messages.reversed())
}
```

### Step 3.2: 重写 messagesList

- [ ] **Step 3: 替换 messagesList 实现**

将当前的 `messagesList` 整体替换为：

```swift
private var messagesList: some View {
    GeometryReader { viewportGeo in
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(
                        Array(reversedMessages.enumerated()),
                        id: \.element.localId
                    ) { revIndex, message in
                        let originalIndex = vm.messages.count - 1 - revIndex
                        VStack(spacing: 0) {
                            MessageBubble(
                                message: message,
                                isSelf: message.message.senderId == vm.currentUserId,
                                isConsecutive: vm.isConsecutive(
                                    message,
                                    previous: originalIndex > 0
                                        ? vm.messages[originalIndex - 1]
                                        : nil
                                ),
                                onRetry: {
                                    Task { await vm.retry(localId: message.localId) }
                                },
                                onOpenImage: {
                                    lightboxBubble = message
                                }
                            )
                            .id(message.localId)

                            if vm.shouldShowTimestamp(at: originalIndex) {
                                TimestampPill(date: message.message.createdAt)
                            }
                        }
                        .scaleEffect(x: 1, y: -1)
                    }

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
                        .scaleEffect(x: 1, y: -1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .background(
                    GeometryReader { contentGeo in
                        let frame = contentGeo.frame(in: .named("chatScroll"))
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: -frame.minY
                            )
                            .preference(
                                key: ContentHeightPreferenceKey.self,
                                value: contentGeo.size.height
                            )
                    }
                )
            }
            .coordinateSpace(name: "chatScroll")
            .scaleEffect(x: 1, y: -1)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { isInputFocused = false }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                scrollOffset = offset
                scrollState.updateOffset(offset)
                handleScrollActivity()
            }
            .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                scrollContentHeight = height
            }
            .overlay(alignment: .trailing) {
                ChatScrollIndicator(
                    metrics: ScrollIndicatorMetrics(
                        contentHeight: scrollContentHeight,
                        viewportHeight: viewportHeight,
                        offset: scrollOffset
                    ),
                    isVisible: isScrolling
                )
            }
            .overlay(alignment: .bottom) {
                newMessagesButton(proxy: proxy)
            }
            .overlay {
                if vm.phase == .loading, vm.messages.isEmpty {
                    ChatSkeletonView()
                        .transition(.opacity)
                }
            }
            .onChange(of: vm.messages.last?.localId) { _, _ in
                handleNewMessage(proxy: proxy)
            }
            .onAppear {
                viewportHeight = viewportGeo.size.height
            }
            .onChange(of: viewportGeo.size.height) { _, newHeight in
                viewportHeight = newHeight
            }
        }
    }
    .background(Color(uiColor: .systemBackground))
}
```

注意：翻转后 cell 内部的 VStack 顺序是 **MessageBubble 在上、TimestampPill 在下**，经过 `.scaleEffect(x: 1, y: -1)` 翻回后，视觉上 TimestampPill 在上、MessageBubble 在下，与原来一致。

### Step 3.3: 添加辅助方法

- [ ] **Step 4: 添加 handleScrollActivity、handleNewMessage、newMessagesButton**

```swift
private func handleScrollActivity() {
    isScrolling = true
    scrollIdleTimer?.cancel()
    scrollIdleTimer = Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            isScrolling = false
        }
    }
}

private func handleNewMessage(proxy: ScrollViewProxy) {
    guard let last = vm.messages.last else { return }
    if last.message.senderId == vm.currentUserId {
        scrollToBottom(proxy, animated: true)
    } else if scrollState.isNearBottom {
        scrollToBottom(proxy, animated: true)
    } else {
        scrollState.recordIncomingMessage()
    }
}

@ViewBuilder
private func newMessagesButton(proxy: ScrollViewProxy) -> some View {
    if scrollState.newMessageCount > 0 {
        Button {
            scrollToBottom(proxy, animated: true)
            scrollState.reset()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                Text("\(scrollState.newMessageCount) 条新消息")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.echoInteractive))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: scrollState.newMessageCount)
    }
}
```

### Step 3.4: 更新 scrollToBottom

- [ ] **Step 5: 替换 scrollToBottom 实现**

```swift
private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
    guard let newestId = vm.messages.last?.localId else { return }
    DispatchQueue.main.async {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(newestId, anchor: .top)
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(newestId, anchor: .top)
            }
        }
    }
}
```

### Step 3.5: 更新 .task 修饰器

- [ ] **Step 6: 简化 .task 修饰器**

将 body 中的 `.task` 从：
```swift
.task {
    vm.attachWSSubscription()
    await vm.load()
    if initialScrollPolicy.markInitialLoadFinished() {
        initialCatchUpScrollTrigger += 1
    }
}
```
改为：
```swift
.task {
    vm.attachWSSubscription()
    await vm.load()
}
```

同时删除 body 中以下两个 `.onChange`（已在新的 messagesList 中用新逻辑替代）：

```swift
// 删除这两个（它们在旧的 messagesList 内部，但如果在 body 中则同样删除）
.onChange(of: vm.messages.last?.localId) { ... }
.onChange(of: initialCatchUpScrollTrigger) { ... }
```

- [ ] **Step 7: 编译验证**

Run: `xcodebuild build -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -20`

Expected: 编译成功（可能有 `ChatInitialScrollPolicy` 未使用的 import 警告，下个 Task 清理）。

- [ ] **Step 8: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatView.swift
git commit -m "feat(ios): refactor chat message list to flipped LazyVStack layout"
```

---

## Task 4: 删除 ChatInitialScrollPolicy

翻转布局天然在底部，初始滚底策略不再需要。

**Files:**
- Delete: `ios-app/EchoIM/Features/Chat/ChatInitialScrollPolicy.swift`
- Delete: `ios-app/EchoIMTests/ChatInitialScrollPolicyTests.swift`

- [ ] **Step 1: 删除文件**

```bash
rm ios-app/EchoIM/Features/Chat/ChatInitialScrollPolicy.swift
rm ios-app/EchoIMTests/ChatInitialScrollPolicyTests.swift
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -20`

Expected: 编译成功，无对 `ChatInitialScrollPolicy` 的引用错误。

- [ ] **Step 3: 运行全量测试**

Run: `xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' 2>&1 | tail -30`

Expected: 全部通过（ChatInitialScrollPolicyTests 不再存在，不会被发现）。

- [ ] **Step 4: 提交**

```bash
git add -A ios-app/EchoIM/Features/Chat/ChatInitialScrollPolicy.swift ios-app/EchoIMTests/ChatInitialScrollPolicyTests.swift
git commit -m "refactor(ios): remove ChatInitialScrollPolicy, replaced by flipped layout"
```

---

## Task 5: 手动验证清单

在模拟器中运行 app，逐项验证以下行为。

**Files:** 无代码变更

- [ ] **Step 1: 首次进入**

打开一个有消息的会话，确认：
- 进入时直接看到最新消息（在底部），无需等待滚动动画
- 骨架屏（skeleton）在加载期间正常显示

- [ ] **Step 2: 键盘避让**

点击输入框：
- 键盘弹出时，消息列表 + 输入栏整体上移到键盘上方
- 消息内容不被遮挡
- 键盘收起后恢复原位
- `scrollDismissesKeyboard(.interactively)` 仍可用（向下拖拽收起键盘）

- [ ] **Step 3: 新消息（在底部）**

在底部时让对方发一条消息：
- 新消息自动出现在可视区域
- 无 "新消息" 浮动按钮出现

- [ ] **Step 4: 新消息（已上滚）**

向上滚动查看旧消息，让对方发消息：
- 不被强制拉回底部
- 出现 "↓ N 条新消息" 浮动按钮
- 多条消息时 N 递增
- 点击按钮后滚到底部，按钮消失

- [ ] **Step 5: 自己发送消息**

向上滚动后自己发一条消息：
- 无论滚动位置如何，一律滚到底部
- 乐观气泡正常显示为 pending → confirmed

- [ ] **Step 6: 加载更早消息**

滚到最顶部：
- "加载更早消息" 按钮在视觉顶部正常显示（文字方向正确）
- 点击后旧消息加载到上方，当前视野不跳动

- [ ] **Step 7: 自定义滚动指示器**

快速滚动消息列表：
- 右侧出现自定义滚动条
- 在底部（最新消息）时指示器在轨道底部
- 在顶部（最旧消息）时指示器在轨道顶部
- 停止滚动后指示器淡出

- [ ] **Step 8: 图片消息**

发送一张图片：
- 图片气泡正常渲染，宽高比正确
- 点击可打开 Lightbox
- pending 遮罩和 "发送中" 标签方向正确（未被翻转）

- [ ] **Step 9: 时间戳分隔线**

消息间隔超过 5 分钟的位置：
- TimestampPill 出现在对应消息上方
- 文字方向和对齐正确

- [ ] **Step 10: 空会话**

从联系人进入一个从未聊过的好友：
- 页面正常显示空状态
- 发送第一条消息后正常展示
