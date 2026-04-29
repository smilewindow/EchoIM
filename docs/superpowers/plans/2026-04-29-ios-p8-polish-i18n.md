# iOS P8 实施计划：打磨 + 国际化 + 触觉反馈 + 验收

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从 P7 的"自己资料可编辑 + 对方资料只读卡"推进到设计文档 §8 P8 的"打磨 + 测试 + Dark Mode + i18n"——作品集发版前的最后一阶段。具体落地：

- **i18n（最大工作量）**：所有 View / ViewModel 中硬编码的中文文案改用 `Text(LocalizedStringKey)` 与 `String(localized:)`；新建单文件双语 `Localizable.xcstrings`（zh-Hans 为开发语言、en 为翻译目标）。预估约 102 条文案。
- **触觉反馈（少量代码）**：新建 `HapticFeedbackProvider` 协议 + `UIKitHapticFeedback` / `NoOpHapticFeedback` 实现；`ChatViewModel.sendText` / `sendImage` 成功后触发 light impact、`ContactsViewModel.respond(accept: true)` 触发 success notification、`accept: false` 触发 warning notification。
- **加载/空/错误态统一**：新建 `Core/UI/StateView.swift`（基于 iOS 17 `ContentUnavailableView` 包装），重构 `ConversationsListView` 与 `FriendsListView` 的全屏空/错态。`UserSearchSheetView` 的"至少输入两个字符 / 没有匹配的用户"是搜索框下方 inline 提示而非全屏占位，**不重构结构**，仅在 Task 7 i18n 扫尾时改文案。
- **键盘处理打磨**：`ChatView` 增加 `.scrollDismissesKeyboard(.interactively)` 与 toolbar `Done` 收键盘；`ProfileEditView` 沿用 `Form` 自带避让，验证不被遮挡。最近 7efea91 / afc9430 已经做了"输入框上浮 + 滚动到底锚点"基础打磨，本任务只补"主动收键盘"通道。
- **Dark Mode 视觉审计**：每个屏幕跑一遍 light / dark 截图 checklist，对发现的 contrast / 颜色错误做修复（从代码扫读看大概率全部已对齐 system semantic color，但需手工验收）。
- **Golden path XCUITest 增强**：新建 `EchoIMUITests/GoldenPathSmokeTests.swift`，覆盖"登录 → 会话列表 → 进入聊天 → **发文字（断言 `chatBubble_text_*` bubble 出现）** → 打开图片 picker（断言 picker 弹出 + 关闭后聊天页仍在）"。**发文字** 走完整端到端断言；**发图片** 走到 picker 弹起 + 关闭，**不**断言"上传后 image bubble 出现" —— 模拟器没有真实相册图，需 `xcrun simctl addmedia` 预置；为避免与 CI 环境耦合，本测试不做这一步。补 image bubble 断言留作未来增强（front matter "已知妥协"补充）。
- **内存泄漏验收**：用 Instruments Allocations 跑三个场景（聊天页反复进出 / logout-login 切换 / 上传重试），文档化无泄漏的验收结果。
- **验收**：Swift Testing 全量通过；XCUITest 全量通过；spec §8 P8 列出的 4 项单测覆盖在 P3-P5 已完成（见下方"现有测试覆盖声明"）；实机过 golden path。

**Architecture:** P8 是横向"打磨"阶段，按"先稳定源码 → 后做本地化扫尾"组织：

1. **i18n 基础设施先建好**（Task 1）：建 `Localizable.xcstrings` 空文件并把项目语言切到 zh-Hans + en。即使本任务一行业务代码都不改，文件存在让后续 `Text("登录")` 自动被 catalog 收集——这是 Apple 新版 Strings Catalog 的工作机制。

2. **打磨类源码改动先做完**（Task 2 ~ Task 5）：HapticFeedback / StateView / 键盘 / Dark Mode。**这些改动里新引入的 `Text("…")` 仍然先写中文字面量**，不做本地化封装——避免"改一处源码、回头补一次 catalog、再改一处源码"的 thrash。

3. **本地化扫尾批量做**（Task 6 ~ Task 8）：源码稳定后一次扫完所有 ViewModel 错误文案 + View 文案 + en 翻译。这一段类似"翻译工作流"，与业务代码解耦。

4. **验收**（Task 9 ~ Task 11）：Golden path XCUITest / 内存泄漏 / 全量回归 + 提交。

**Tech Stack:** SwiftUI（`Text(LocalizedStringKey)` / `Button(LocalizedStringKey)` / `Section(LocalizedStringKey)` / `LocalizedStringResource`）、`String(localized:)`（ViewModel 错误文案）、`Localizable.xcstrings`（Strings Catalog）、`UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`（UIKit 触觉 API）、`ContentUnavailableView`（iOS 17）、`.scrollDismissesKeyboard(.interactively)` / `@FocusState`、Swift Testing、XCUITest、Instruments Allocations。

**TDD 适用范围（与 P1-P7 一致）：**

- **纯逻辑 → TDD**：
  - `HapticFeedbackProvider` 注入点：`ChatViewModel.sendText` 成功路径调用 `light` / `sendImage` 成功路径调用 `light`；`ContactsViewModel.respond` accept 走 `success`、decline 走 `warning`。注入 `NoOpHapticFeedback` 的子类记录调用，断言被命中。
  - `String(localized:)` 编译期检查：跑一次 build 验证所有 key 落进 catalog（Xcode 自动抽取）。
- **View → 编译 + 手工 + 既有 XCUITest smoke**：
  - StateView 重构：xcodebuild build 通过 + 既有 ConversationsListView / FriendsListView 的 XCUITest 验证 accessibilityIdentifier 不破。
  - 键盘打磨：手工试输入框上浮 / 滚动消失 / toolbar Done。
  - Dark Mode：手工 light / dark 截图对照 checklist。
  - i18n：手工切系统语言到英文，验证关键路径（登录页 / 聊天页 / Me 页）显示英文。
- **新增 XCUITest（GoldenPathSmokeTests）**：覆盖完整发文字 + 发图片链路，断言 `chatBubble_text_*` / `chatBubble_image_*` 出现。

**服务端契约改动：** **无**。P8 不动 `server/` 任何文件。所有新增/修改命令都不应碰 `server/`。

**现有测试覆盖声明（spec §8 P8 4 项单测项目，已在 P3-P5 完成）：**

> spec §8 P8 列出"Swift Testing 单元测试：ChatViewModel gap detection 三场景 / ImageSendStage 重试跳过 / ReconnectPolicy 退避序列 / WS 事件 decode"。这 4 项**全部在前序阶段已实现**，P8 不重复造，仅在 Task 11 验收时确认这些测试在 P8 改动后仍然通过。具体定位：

| spec 单测项 | 已存在的测试文件 | 关键测试 |
|---|---|---|
| ChatViewModel gap detection 三场景 | `ios-app/EchoIMTests/ChatViewModelCacheTests.swift` | `loadRendersCachedMessagesBeforeNetwork`（场景 A 冷启动）/ `loadWritesNetworkResultToCache`（场景 A 落盘）/ `refetchLoopsUntilSmallPage`（场景 C cursor 翻页前进直到 < 50 停止）/ `loadOlderFullyServedByCacheSkipsNetwork`（上滑全本地命中）/ `loadOlderPartialCacheHitsSupplementsFromRemote`（上滑本地不够补远端） |
| ImageSendStage 重试跳过 | `ios-app/EchoIMTests/ImageSendStageTests.swift` | 已上传后重试不重新调 upload。同时 `ChatViewModelImageTests.swift` 也覆盖 ChatViewModel 层重试的端到端行为。 |
| ReconnectPolicy 退避序列 | `ios-app/EchoIMTests/ReconnectPolicyTests.swift` | 1s → 2s → 4s → … → 30s capped；reset 触发后回 1s |
| WS 事件 decode | `ios-app/EchoIMTests/WSEventDecodingTests.swift` | 所有 WSEvent case decode；`FriendRequestDecodingTests` / `MessageDecodingTests` / `ConversationDecodingTests` / `UserProfileDecodingTests` 是补充编解码覆盖 |

**关键 iOS 17 / SwiftUI 契约速查（实现前必须读懂）：**

- **Strings Catalog (`.xcstrings`) 自动抽取机制**：`Text("登录")` 只要参数是字符串字面量，编译时 Xcode 会把 `"登录"` 加进 catalog 当 key（即 source language string）。`Text("Hello \(name)")` 的 key 是 `"Hello %@"`（`String` → `%@`）；`Text("用户 \(id)")` 当 `id: Int` 时 key 是 `"用户 %lld"`（Swift `Int` → `%lld`）。**第一次 xcodebuild build 之后** catalog 文件里就出现这些 key 占位行，再手工填 en 翻译。
- **`String(localized:)` 与 `Text(LocalizedStringKey)` 的差异**：`Text` / `Button(_:)` / `Section(_:)` 等接受 `LocalizedStringKey` 的 SwiftUI 入口**自动**走本地化（编译时收集）。但 ViewModel / 错误文案这种返回 `String` 的位置必须手写 `String(localized: "邮箱和密码不能为空")` 才能被 catalog 收集——直接 `let s = "..."` 会被 catalog 跳过。
- **错误信息透传不本地化**：`String(describing: error)` 是 Swift error 的英文 description（如 `"APIError.unauthorized"`）。这是开发态文案，**P8 不为其加翻译层**；Catalog 里只翻译"我们自己写死的中文文案"。`phase = .error(String(describing: error))` / `errorMessage = String(describing: error)` 等位置不要改。
- **`ContentUnavailableView`（iOS 17+）**：标准空/错态容器。`ContentUnavailableView { Label("...", systemImage: "...") } description: { ... } actions: { ... }`。提供 `.search` preset 但本项目都用 plain 形式。
- **`@FocusState` + `@FocusState.Binding`**：在 SwiftUI 中收键盘的标准做法是 `isFocused = false`；本项目 `ChatView` 已经用 `@FocusState private var isInputFocused: Bool` + 一个 `simultaneousGesture(TapGesture)` 在消息列表点击时 dismiss。`.scrollDismissesKeyboard(.interactively)` 是 iOS 16+ ScrollView modifier，让用户向下滑动消息列表时键盘跟随手指拉下。
- **`UIImpactFeedbackGenerator` 必须先 `prepare()` 再 `impactOccurred()` 才低延迟**：但作品级里"prepare 后 0.5s 内不触发会失效"对我们用例不重要——直接 `impactOccurred()` 也工作，只是首次稍微迟一点。本项目 `HapticFeedback` 实现里**不做 prepare**，简单干净。

**关键 Strings Catalog 操作速查（实现时常踩的坑）：**

- **xcstrings 文件位置**：放在 `ios-app/EchoIM/Localizable.xcstrings`（与 `EchoIMApp.swift` 同级）。**不是**新建 `Resources/` 目录——多此一举，而且项目用 `PBXFileSystemSynchronizedRootGroup` 子目录如果没注册到 target 反而报"resource not in bundle"。
- **首次 build 后才能编辑 catalog**：catalog 是空 JSON 时 Xcode 不会显示 keys。先写一行 `Text("hello")`、build 一次、再回 catalog 才看到 key 出现。所以 Task 1 只建空文件 + 配 Info.plist + build 通过即可，**不要**在 Task 1 里就开始填翻译。
- **catalog 状态字段**：每个 key 有 `state: "translated" | "needs_review" | "stale"`。我们的目标是所有 zh-Hans 与 en 都是 `translated`。Xcode 会自动把"源码删掉对应字符串"的 key 标 `stale`——这种 stale 项要么删要么改回（在 Task 8 验收）。
- **预览/UITest 不会自动切语言**：XCUITest 默认跑 development language（zh-Hans）。`accessibilityIdentifier` 必须是稳定 ASCII，不要本地化。**所有现有 / 新增的 `accessibilityIdentifier(...)` 都保持英文常量字符串**。

**不在 P8 范围（明确延后）：**

- **`Text(verbatim:)` / `String(describing:)` 这些故意非本地化的位置**：保留原状。
- **数字 / 日期 / 货币本地化**：`RelativeDateTimeFormatter` 已经走系统 locale；`unreadCount` 显示是单纯 `\(count)` 数字插值，不区分千分位（作品级范围内 unread 不会到 1000）。
- **多个 plural 形式**：catalog 支持 `.stringsdict`-like 复数变体，但本项目没有"\(count) message(s)"这种文案，全部走单一形式即可。
- **超过 zh-Hans + en 的语言**：spec §8 P8 写的是"zh / en"，不做 zh-TW / ja / ko。
- **iPad 适配 / 横屏 / Dynamic Type 极端档（XL+）**：spec §0 已经声明 iPhone-only / 不做 iPad 自适应。Dynamic Type 跑到 default + accessibility-large 视觉无破即视为通过。
- **APNs 推送**：spec §10 已声明不做。
- **错误信息中英映射**：上文已说明，错误透传不本地化。
- **触觉反馈接收新消息**：避免噪音；只在用户主动行为（发消息、响应申请）触发。
- **ChatViewModel 内显式注入 HapticFeedbackProvider**：通过 init 默认参数 `= UIKitHapticFeedback()` 注入，无需改 AppContainer 路径。`ContactsViewModel` 同理。
- **重新跑 spec §8 P8 列出的 4 项单测**：已在 P3-P5 完成（见上方"现有测试覆盖声明"），不复刻。

**已知妥协：**

- **用 Strings Catalog (`Localizable.xcstrings`) 而非传统 `Localizable.strings` + `.stringsdict`**：spec §8 P8 写的是"`Localizable.strings` zh / en"。这里偏离 spec 用 Strings Catalog，原因有三：（a）项目 baseline 是 iOS 17+，Strings Catalog 是 Apple 自 iOS 17 起的官方推荐；（b）单文件双语 + Xcode 编辑器内置 + 编译期自动从源码抽取 key，比手维护双 `.strings` 文件少一层"忘了更新某条"的失误；（c）内置 plural / device / language variants（即便本项目不用）。**实操结果**：开发者 / Xcode 工作流不变，只是磁盘上是 `.xcstrings` JSON 而不是 `.strings` plist。
- **触觉反馈不做"系统设置降级"判断**：iOS Settings 里用户可关掉系统触觉，OS 本身会忽略我们的请求；不再在 App 层判断 `UIDevice.current.userInterfaceIdiom != .pad` / `traitCollection.preferredContentSizeCategory` 之类的非相关 trait。
- **Dark Mode 修复采用"先审计、按需修"**：从代码扫读看大部分 view 已用 system semantic color (`Color(uiColor: .systemBackground)` / `.secondary` / `Color.accentColor`），预期视觉验收时只有少量 contrast 问题。Task 5 plan 里把"截图清单"作为产出物，问题真出现在哪里再写小 patch；**不在本 plan 里预先规划具体修复 step**——按需 inline 加 step。
- **StateView 是包装而非替换**：iOS 17 `ContentUnavailableView` 已经够用；`Core/UI/StateView.swift` 只做轻量 wrapper（暴露 `StateView.empty(...)` / `StateView.error(message:retry:)` 这种我们项目语义的 factory），让调用点更短、accessibility identifier 统一。不是从零造组件。
- **Golden path XCUITest 不覆盖好友请求 / 注册新账号**：`FriendRequestCrossAccountSmokeTests` 已经覆盖跨账号好友流程；spec §8 P8 字面要求是"登录 → 会话列表 → 发文字 → 发图片"，本任务严格按字面来，不扩展。
- **Golden path 的"发图片"只到 picker 弹起，不断言图片 bubble 出现**：模拟器没有真实相册图，要走"上传 → 收到 server 确认 → image bubble 渲染"端到端必须先 `xcrun simctl addmedia <fixture.jpg>` 注入测试图，再用系统级 picker 自动化（XCUI 跨 process 选第一张）。这是合理工程，但 CI 环境下要保证 simctl 命令稳定执行 + fixture 路径稳定 + 图片选择 element id 稳定，三者任一缺失都会 flaky。本作品级范围内退化为"picker 能弹 = 发图入口路径完备"，等同于现有 `ImageSendSmokeTests` 的覆盖深度。文字消息走端到端断言，已能覆盖 "send + WS / REST 合并 + bubble 渲染" 整条链路 —— 图片链路与文字链路在 `ChatViewModel.executeImageSend` / `mergeServerResult` 路径上**同源**，文字端到端通过即图片端到端逻辑的核心代码路径已被自动验证。
- **内存泄漏检查不写 XCTest 自动化**：Instruments Allocations 跑法是手工 + 视觉判断（"反复操作后 Persistent Bytes 稳定"），没有合理的 CI 化路径。Task 10 的产出是 plan 末尾"实机偏差"节里写"已跑 X 轮、未观察泄漏"，没有自动化。
- **i18n 中插值字符串的实参顺序**：`Text("用户 \(id)")` → catalog key `"用户 %lld"` → en 翻译 `"User %1$lld"`（用 positional argument）。如果某条文案在不同语言里参数顺序不同，**写 en 时必须用 `%1$lld` / `%2$@` 这种 positional spec**。本项目检查后**没有需要变序**的 case（中英参数都在末尾），所以可以省略 positional spec，但 plan 里给一个示例的展示保险（Task 8 给）。

**重要不变式（实现前必须读懂，实现中容易踩到）：**

1. **ViewModel 错误文案改用 `String(localized:)`**：`LoginViewModel.toast = "登录失败，请重试"` / `ContactsViewModel.errorMessage = "..."` 这种**自定义中文**必须改成 `String(localized: "登录失败，请重试")`。**但** `String(describing: error)` / `String(reflecting: ...)` 这种 Swift 系统输出**保留原状**，不本地化。
2. **`accessibilityIdentifier` 永远是 ASCII 常量**：本地化与 a11y identifier 是两回事——前者 Catalog 收集，后者 XCUITest 用。两者走完全不同 API，互不影响。但工程师容易把 `accessibilityLabel("发送")` 与 `accessibilityIdentifier("chatSend")` 混淆——前者本地化、后者不本地化。
3. **触觉反馈调用点必须在"成功路径"上**：`sendText` / `sendImage` 里 `mergeServerResult` 之后才能触发 `light()`；`markFailed` 路径不触发（避免给用户假成功反馈）。`ContactsViewModel.respond` 同理：必须在 `try await requestRepo.respond(...)` 不抛错之后才触发 success/warning，catch 分支不触发。
4. **HapticFeedbackProvider 注入要走 init 默认参数**：`ChatViewModel.init(..., haptics: HapticFeedbackProvider = UIKitHapticFeedback(), ...)`。这样既保证生产代码自动用 UIKit 实现、又允许测试注入 NoOp / 计数 mock，不需要改 AppContainer / UserSession 任何工厂方法。
5. **StateView 用包装而不是替换**：现有 `errorState(_ message: String)` / `emptyState` 调用点的 `accessibilityIdentifier` 必须保持。重构后断言"既有 XCUITest 仍通过"。
6. **`.scrollDismissesKeyboard(.interactively)` 在 ChatView 的 ScrollView 上加**：不是在 LazyVStack / 内层视图上加。会被 SwiftUI 沿层级向上 propagate，但官方推荐就近放在 ScrollView 上一层。
7. **Strings Catalog 文件不能漏入 target membership**：新建 `.xcstrings` 后**必须**在 Xcode 里勾选 EchoIM target 否则不打包进 .app。`PBXFileSystemSynchronizedRootGroup` 默认会把 EchoIM/ 下文件加进 target，但偶尔卡住——Task 1 验证步骤里有 `xcodebuild build` + 检查 build/Debug-iphonesimulator/EchoIM.app/ 下确实有 `.xcstrings` 编译后的 `Localizable.strings`。
8. **`HapticFeedback` 文件不放 `Core/UI/` 也不放 `Core/Networking/`**：放 `Core/Utilities/HapticFeedback.swift`（与 `ImageCompressor` / `AvatarImageCompressor` / `DateParser` 平级；它们都是无状态/低复杂度的工具）。
9. **`StateView.swift` 放 `Core/UI/`**：与 `AvatarView` / `PresenceDot` / `ZoomableImageView` 同级——都是无 VM 的纯展示组件。
10. **不要用 `LocalizedStringResource`**：iOS 16+ 的 `LocalizedStringResource` 也能从 catalog 取 key，但它在 SwiftUI Text 里更绕（要 `Text(.init(localized: ...))`）。本项目统一用 `Text("中文字面量")`（视图层走 LocalizedStringKey 自动）+ `String(localized: "中文字面量")`（VM 层）这两条路径，不引入第三种。

---

## 开发环境前提

沿用 P1-P7。命令约定（**`$BUILD` / `$TEST` / `$UITEST` 在所有 Step 里等价于下面三条 `xcodebuild` 命令**）：

```bash
# iOS 编译（Debug）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# iOS 单测（Swift Testing + XCTest 全量）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMTests

# iOS XCUITest（smoke 全量）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMUITests
```

> 如本机没有 `OS=latest` 的 iPhone 15 目标，按 P5-P7 经验改 `-destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15'`。

工作目录约定：所有 iOS 路径以 `ios-app/EchoIM/` 开头。**P8 不动 `server/`**。

---

## 文件结构

新增文件：

```
ios-app/EchoIM/
├── Localizable.xcstrings                            // 新：Strings Catalog 单文件双语（zh-Hans + en）
├── Core/
│   ├── UI/
│   │   └── StateView.swift                          // 新：ContentUnavailableView 包装（empty / error 两种工厂）
│   └── Utilities/
│       └── HapticFeedback.swift                     // 新：HapticFeedbackProvider 协议 + UIKitHapticFeedback / NoOpHapticFeedback
ios-app/EchoIMTests/
├── HapticFeedbackInjectionTests.swift               // 新：ChatViewModel / ContactsViewModel 注入点断言
ios-app/EchoIMUITests/
└── GoldenPathSmokeTests.swift                       // 新：登录 → 发文字 → 发图片端到端断言
```

修改文件（按 Task 顺序）：

```
ios-app/
├── Info.plist                                       // 加 CFBundleLocalizations 数组（zh-Hans + en）；CFBundleDevelopmentRegion 仍走 $(DEVELOPMENT_LANGUAGE) 占位符
├── EchoIM.xcodeproj/project.pbxproj                 // PBXProject.developmentRegion: en → "zh-Hans"；knownRegions 加 "zh-Hans"
└── EchoIM/
    ├── Core/
    │   ├── UI/
    │   │   └── PresenceDot.swift                    // .accessibilityLabel(Text("在线"))
    │   └── Networking/Models/
    │       └── FriendRequest.swift                  // displayTitle(fallback:) 默认值 "用户" → String(localized: "用户")
    └── Features/
        ├── Chat/
        │   ├── ChatView.swift                       // .scrollDismissesKeyboard + toolbar Done；本地化文案
        │   ├── ChatViewModel.swift                  // performSend / executeImageSend 的 mergeServerResult 之后调 haptics.lightImpact()；HapticFeedbackProvider 默认参数注入
        │   ├── MessageBubble.swift                  // .accessibilityIdentifier("chatBubble_text_\(localId)")；本地化文案
        │   └── ImageMessageBubble.swift             // .accessibilityIdentifier("chatBubble_image_\(localId)")；本地化文案
        ├── Conversations/
        │   └── ConversationsListView.swift          // emptyState / errorState 改用 StateView；本地化文案
        ├── Contacts/
        │   ├── ContactsView.swift                   // 本地化（联系人 / nav title）
        │   ├── ContactsViewModel.swift              // respond accept/decline 触发 haptics.success/warning；errorMessage 本地化
        │   ├── FriendsListView.swift                // emptyState 改用 StateView；本地化文案
        │   ├── FriendRequestsSheetView.swift        // 本地化（同意/拒绝 / 待处理 / 已发送 / 历史 / "用户 \(id)" 插值）
        │   ├── UserSearchSheetView.swift            // **不动结构**；只在 i18n 扫尾改文案
        │   └── UserDetailView.swift                 // 本地化（在线 / 离线 / 资料 / @\(username)）
        ├── Auth/
        │   ├── LoginView.swift                      // 本地化（登录 / 邮箱 / 密码 / 没有账号？去注册 / 登录失败 alert / 好）
        │   ├── LoginViewModel.swift                 // toast / 错误文案改用 String(localized:)
        │   ├── RegisterView.swift                   // 本地化（注册 / 邀请码 / 用户名 / 邮箱 / 密码 / 已有账号？返回登录 / 注册失败 alert / 好）
        │   └── RegisterViewModel.swift              // 字段错误 + toast 改用 String(localized:)
        ├── Me/
        │   ├── MeView.swift                         // 本地化（编辑资料 / 清除聊天缓存 / 登出 / 我 / 清除…对话框 / 取消 / 清除中…）
        │   ├── ProfileEditView.swift                // 本地化（编辑资料 / 头像 / 显示名称 / 保存 / 上传中… / 上传失败：\(error) 等）
        │   └── ProfileEditViewModel.swift           // uploadError 文案保留 String(describing:) 透传，不动
        └── Main/
            └── MainTabView.swift                    // 本地化 3 个 Label（聊天 / 联系人 / 我）
```

每个新增文件单一职责。`HapticFeedback.swift` 与 `StateView.swift` 互不依赖；`Localizable.xcstrings` 由 Xcode 自动维护（开发者只填翻译列）。

---

## Task 1: i18n 基础设施 — Strings Catalog 文件 + 项目语言配置

**Files:**
- Create: `ios-app/EchoIM/Localizable.xcstrings`
- Modify: `ios-app/Info.plist`（**注意**：Info.plist 实际位置在 `ios-app/Info.plist`，**不是** `ios-app/EchoIM/Info.plist`；当前 `CFBundleDevelopmentRegion` 是 `$(DEVELOPMENT_LANGUAGE)` 占位符）
- Modify: `ios-app/EchoIM.xcodeproj/project.pbxproj`（顶层 `PBXProject` 节的 `developmentRegion = en` → `"zh-Hans"`，`knownRegions = (en, Base,)` → `("zh-Hans", en, Base,)`）

设计依据：spec §8 P8 "i18n: Localizable.strings zh / en"（本计划用 Strings Catalog，原因见 front matter "已知妥协"第一条）。

> **实现说明**：项目使用 `PBXFileSystemSynchronizedRootGroup`（Xcode 16+），新建 `.xcstrings` 文件无需手动改 `project.pbxproj` 加 file reference —— 文件系统变更会被 Xcode 自动识别并加入 target。**但** `developmentRegion` / `knownRegions` 这两个顶层 PBXProject 字段必须手动改，否则 source language 仍是 `en`，与本计划"用 zh-Hans 当开发语言"的前提冲突，catalog 行为会出现异常。
>
> **Info.plist 当前值**：`CFBundleDevelopmentRegion = $(DEVELOPMENT_LANGUAGE)`，其中 `$(DEVELOPMENT_LANGUAGE)` 在 build 时被 Xcode 替换为 `developmentRegion`（PBX 字段）。Step 1 改完 PBX 后即生效，Info.plist 的 `CFBundleDevelopmentRegion` 不需要写死字符串；但 Step 2 把 `CFBundleLocalizations` 数组显式声明，让"未来增加新 lproj"时 Xcode 也能稳定识别。

- [x] **Step 1: 改 project.pbxproj 的 developmentRegion 与 knownRegions**

Read `ios-app/EchoIM.xcodeproj/project.pbxproj` 定位到 line 195-210 区段（搜索 `developmentRegion = en;`）。

Edit 把：
```
developmentRegion = en;
				hasScannedForEncodings = 0;
				knownRegions = (
					en,
					Base,
				);
```

改成：
```
developmentRegion = "zh-Hans";
				hasScannedForEncodings = 0;
				knownRegions = (
					"zh-Hans",
					en,
					Base,
				);
```

> `zh-Hans` 含连字符，pbxproj 里**必须加双引号**；`en` / `Base` 不含特殊字符可不加（保持原样）。改完后跑 `xcodebuild -project ios-app/EchoIM.xcodeproj -list` 确认无 PBX 解析错误。

- [x] **Step 2: 显式声明 Info.plist 的 CFBundleLocalizations**

Read `ios-app/Info.plist` 完整内容确认结构。

Edit 在 `<key>CFBundleDevelopmentRegion</key><string>$(DEVELOPMENT_LANGUAGE)</string>` 之后插入：

```xml
<key>CFBundleLocalizations</key>
<array>
    <string>zh-Hans</string>
    <string>en</string>
</array>
```

> `CFBundleDevelopmentRegion = $(DEVELOPMENT_LANGUAGE)` 保留原样——它会在 build 时被 PBX 的 `developmentRegion`（Step 1 已改成 `zh-Hans`）替换。

- [x] **Step 3: 创建空的 Strings Catalog**

Use Write 创建 `ios-app/EchoIM/Localizable.xcstrings`，内容：

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : { },
  "version" : "1.0"
}
```

> 这是 Strings Catalog 的最小空壳，跟 Xcode 16 "New File → Strings Catalog" 等价。`strings : {}` 由 Xcode 在后续 build 时自动填充收集到的 key。

- [x] **Step 4: 编译，验证 Strings Catalog 被识别且打包**

Run: `$BUILD`

Expected: build SUCCEEDED。无 `error: localizable strings file ...` 这种红字。

确认 catalog 被打包：

```bash
find ~/Library/Developer/Xcode/DerivedData/EchoIM-* -name "Localizable.strings" -path "*/zh-Hans.lproj/*" 2>/dev/null | head -3
```

Expected: 至少一条路径，形如 `.../Build/Products/Debug-iphonesimulator/EchoIM.app/zh-Hans.lproj/Localizable.strings`（catalog 在 build 时被 Xcode 编译成传统 `.strings` 双 lproj 输出）。如果没有 .lproj 路径出现，说明 catalog 没加进 target 或 PBX `developmentRegion` 改动未生效。**调试**：在 Xcode GUI 打开 project → Info tab → Localizations 应能看到 "Chinese, Simplified - Development Language" 与 "English"；以及 Localizable.xcstrings 的 Target Membership 勾上 EchoIM。

- [x] **Step 5: Commit**

```bash
git add ios-app/EchoIM/Localizable.xcstrings \
        ios-app/Info.plist \
        ios-app/EchoIM.xcodeproj/project.pbxproj
git commit -m "feat(ios): add empty Localizable.xcstrings + zh-Hans development language"
```

**Task 1 实现记录（2026-04-29）**

- 已完成：`developmentRegion` 改为 `"zh-Hans"`，`knownRegions` 增加 `"zh-Hans"`；`Info.plist` 增加 `CFBundleLocalizations`（`zh-Hans` / `en`）；新增空 `ios-app/EchoIM/Localizable.xcstrings`。
- 验证：`xcodebuild -project ios-app/EchoIM.xcodeproj -list` 通过；`xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15' build` 通过；`xcrun xcstringstool compile --dry-run --output-directory /tmp/echoim-xcstrings-check ios-app/EchoIM/Localizable.xcstrings` 通过；`jq empty ios-app/EchoIM/Localizable.xcstrings` 通过。
- 实现中问题：计划里的默认 destination `platform=iOS Simulator,name=iPhone 15` 在本机解析为 `OS=latest`，但本机没有 latest 版 iPhone 15 模拟器；已按计划备用路径改用 `OS=17.5`。另外空 catalog 构建后不会生成空的 `zh-Hans.lproj/Localizable.strings`，但 build 日志显示 `xcstringstool compile --dry-run` 处理了 `Localizable.xcstrings`，DerivedData 里也生成了 `GeneratedStringSymbols_Localizable*`，因此判断为“空 catalog 无输出”而非 target 未识别。

---

## Task 2: HapticFeedback 协议 + 实现 + 注入点

**Files:**
- Create: `ios-app/EchoIM/Core/Utilities/HapticFeedback.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift`
- Test: `ios-app/EchoIMTests/HapticFeedbackInjectionTests.swift`

设计依据：spec §8 P8 "触觉反馈（发消息、好友通过）"、不变式 3 / 4、front matter "TDD 适用范围"。

- [x] **Step 1: 写测试 — HapticFeedback 注入断言**

```swift
// ios-app/EchoIMTests/HapticFeedbackInjectionTests.swift
import Foundation
import Testing
@testable import EchoIM

@MainActor
final class RecordingHaptics: HapticFeedbackProvider {
    private(set) var lightCount = 0
    private(set) var successCount = 0
    private(set) var warningCount = 0

    func lightImpact() { lightCount += 1 }
    func success() { successCount += 1 }
    func warning() { warningCount += 1 }
}

@MainActor
@Suite("HapticFeedback 注入点")
struct HapticFeedbackInjectionTests {
    private func makePeer() -> UserProfile {
        UserProfile(id: 9, username: "peer", displayName: nil, avatarUrl: nil)
    }

    /// ChatViewModel.sendText 成功路径触发 lightImpact 一次。
    @Test
    func sendTextSuccessTriggersLightImpact() async throws {
        final class Repo: MessageRepository, @unchecked Sendable {
            func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] { [] }
            func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
                Message(id: 100, conversationId: 1, senderId: 0, body: body, messageType: "text",
                        mediaUrl: nil, createdAt: Date(), clientTempId: clientTempId)
            }
            func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
                fatalError("not used")
            }
            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: Repo(),
            wsClient: nil,
            tokenProvider: { "tok" },
            haptics: haptics
        )
        await vm.sendText("hi")
        #expect(haptics.lightCount == 1)
        #expect(haptics.successCount == 0)
        #expect(haptics.warningCount == 0)
    }

    /// ChatViewModel.sendText 失败路径不触发 haptic。
    @Test
    func sendTextFailureDoesNotTriggerHaptic() async throws {
        struct Boom: Error {}
        final class Repo: MessageRepository, @unchecked Sendable {
            func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] { [] }
            func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
                throw Boom()
            }
            func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
                fatalError("not used")
            }
            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: Repo(),
            wsClient: nil,
            tokenProvider: { "tok" },
            haptics: haptics
        )
        await vm.sendText("hi")
        #expect(haptics.lightCount == 0)
    }

    /// ChatViewModel.sendCompressedImage 成功路径触发 lightImpact 一次。
    /// 用 sendCompressedImage（不依赖 UIImage 编码），更易在测试中稳定触发。
    @Test
    func sendImageSuccessTriggersLightImpact() async throws {
        final class Repo: MessageRepository, @unchecked Sendable {
            func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] { [] }
            func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
                fatalError("not used")
            }
            func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
                Message(id: 200, conversationId: 1, senderId: 0, body: nil, messageType: "image",
                        mediaUrl: mediaUrl, createdAt: Date(), clientTempId: clientTempId)
            }
            func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {}
        }
        final class Upload: UploadRepository, @unchecked Sendable {
            func uploadMessageImage(data: Data, token: String) async throws -> String {
                "/uploads/messages/0-1234567890.jpg"
            }
            func uploadAvatar(data: Data, token: String) async throws -> String {
                fatalError("not used")
            }
        }
        let haptics = RecordingHaptics()
        let vm = ChatViewModel(
            route: .peer(makePeer()),
            currentUserId: 0,
            messageRepo: Repo(),
            wsClient: nil,
            uploadRepo: Upload(),
            tokenProvider: { "tok" },
            haptics: haptics
        )
        await vm.sendCompressedImage(data: Data([0xFF, 0xD8, 0xFF]), width: 100, height: 100)
        #expect(haptics.lightCount == 1)
        #expect(haptics.successCount == 0)
        #expect(haptics.warningCount == 0)
    }

    /// ContactsViewModel.respond accept 触发 success。
    @Test
    func respondAcceptTriggersSuccess() async throws {
        final class FriendRepo: FriendRepository, @unchecked Sendable {
            func list(token: String) async throws -> [Friend] { [] }
        }
        final class ReqRepo: FriendRequestRepository, @unchecked Sendable {
            func listIncoming(token: String) async throws -> [FriendRequest] { [] }
            func listSent(token: String) async throws -> [FriendRequest] { [] }
            func listHistory(token: String) async throws -> [FriendRequest] { [] }
            func send(recipientId: Int, token: String) async throws -> FriendRequest {
                fatalError("not used")
            }
            func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest {
                FriendRequest(id: id, senderId: 1, recipientId: 2,
                              status: accept ? .accepted : .declined,
                              createdAt: Date(), updatedAt: Date(),
                              username: nil, displayName: nil, avatarUrl: nil, direction: nil)
            }
        }
        let haptics = RecordingHaptics()
        let vm = ContactsViewModel(
            friendRepo: FriendRepo(),
            requestRepo: ReqRepo(),
            tokenProvider: { "tok" },
            haptics: haptics
        )
        await vm.respond(requestId: 1, accept: true)
        #expect(haptics.successCount == 1)
        #expect(haptics.warningCount == 0)
    }

    /// ContactsViewModel.respond decline 触发 warning。
    @Test
    func respondDeclineTriggersWarning() async throws {
        final class FriendRepo: FriendRepository, @unchecked Sendable {
            func list(token: String) async throws -> [Friend] { [] }
        }
        final class ReqRepo: FriendRequestRepository, @unchecked Sendable {
            func listIncoming(token: String) async throws -> [FriendRequest] { [] }
            func listSent(token: String) async throws -> [FriendRequest] { [] }
            func listHistory(token: String) async throws -> [FriendRequest] { [] }
            func send(recipientId: Int, token: String) async throws -> FriendRequest { fatalError() }
            func respond(id: Int, accept: Bool, token: String) async throws -> FriendRequest {
                FriendRequest(id: id, senderId: 1, recipientId: 2,
                              status: accept ? .accepted : .declined,
                              createdAt: Date(), updatedAt: Date(),
                              username: nil, displayName: nil, avatarUrl: nil, direction: nil)
            }
        }
        let haptics = RecordingHaptics()
        let vm = ContactsViewModel(
            friendRepo: FriendRepo(),
            requestRepo: ReqRepo(),
            tokenProvider: { "tok" },
            haptics: haptics
        )
        await vm.respond(requestId: 1, accept: false)
        #expect(haptics.warningCount == 1)
        #expect(haptics.successCount == 0)
    }
}
```

> 测试中 `MessageRepository` / `FriendRepository` / `FriendRequestRepository` 的具体方法签名与项目现状一致；如签名漂移，按 `ios-app/EchoIM/Features/Chat/MessageRepository.swift` / `Features/Contacts/FriendRepository.swift` / `Features/Contacts/FriendRequestRepository.swift` 实际形态对齐。

- [x] **Step 2: 跑测试，验证失败**

Run: `$TEST` 或更精细：
```bash
xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMTests/HapticFeedbackInjectionTests
```

Expected: 编译失败 ——`HapticFeedbackProvider` 类型不存在 / `ChatViewModel.init` 没有 `haptics:` 参数 / `ContactsViewModel.init` 没有 `haptics:` 参数。这是 TDD 第一阶段的预期。

- [x] **Step 3: 实现 HapticFeedback.swift**

Use Write 创建 `ios-app/EchoIM/Core/Utilities/HapticFeedback.swift`：

```swift
import UIKit

/// 用户主动行为成功后给的轻量触觉信号。生产用 UIKitHapticFeedback；测试用 NoOpHapticFeedback。
@MainActor
protocol HapticFeedbackProvider: AnyObject {
    /// 发消息成功 / 简单确认。强度: light。
    func lightImpact()
    /// 接受好友请求等正向操作。
    func success()
    /// 拒绝好友请求等负向操作。
    func warning()
}

@MainActor
final class UIKitHapticFeedback: HapticFeedbackProvider {
    func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

@MainActor
final class NoOpHapticFeedback: HapticFeedbackProvider {
    func lightImpact() {}
    func success() {}
    func warning() {}
}
```

> 不做 `prepare()`：见 front matter "关键 iOS 17 / SwiftUI 契约速查" 最后一条；首次稍迟一点不影响 UX。

- [x] **Step 4: 改 ChatViewModel —— init 注入 haptics + 在 REST 成功路径调 light()**

Edit `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`：

(a) 在 `MARK: - Dependencies` 区添加属性（`typingSender` 之后）：

```swift
private let haptics: HapticFeedbackProvider
```

(b) 在 `init(...)` 末尾参数列表加 `haptics: HapticFeedbackProvider = UIKitHapticFeedback()`，并在 `init` 内赋值 `self.haptics = haptics`。

(c) **在 `performSend` 的 `mergeServerResult(result, tempId: tempId)` 之后**加 `haptics.lightImpact()`：

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
        haptics.lightImpact()                       // 新增（不变式 3）
    } catch {
        markFailed(tempId: tempId, error: error)
    }
}
```

(d) **在 `executeImageSend` 的 `mergeServerResult(result, tempId: tempId)` + `imageSendStages.removeValue(forKey: tempId)` 之后**加 `haptics.lightImpact()`：

```swift
do {
    let result = try await messageRepo.sendImage(
        recipientId: peer.id,
        mediaUrl: mediaURL,
        clientTempId: tempId,
        token: token
    )
    mergeServerResult(result, tempId: tempId)
    imageSendStages.removeValue(forKey: tempId)
    haptics.lightImpact()                           // 新增（不变式 3）
} catch {
    markFailed(tempId: tempId, error: error)
}
```

> **关键不放 `mergeServerResult` 内部的原因**：`mergeServerResult` 同时被 REST 成功路径（`performSend` / `executeImageSend`）和 WS echo 路径（`handleIncomingMessage` 里 `incoming.senderId == currentUserId && clientTempId != nil` 分支）调用 —— 一条自己发的消息会被合并两次。如果在 mergeServerResult 第一行触发 haptic，用户发一条会震两下。**只在 REST 成功路径触发**，WS echo 是"已经震过的消息又被服务端再确认一遍"，不重复反馈。

- [x] **Step 5: 改 ContactsViewModel —— init 注入 haptics + respond 成功后按 accept 调 success/warning**

Edit `ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift`：

(a) 加属性：

```swift
private let haptics: HapticFeedbackProvider
```

(b) `init` 加默认参数 `haptics: HapticFeedbackProvider = UIKitHapticFeedback()` + 内部 `self.haptics = haptics`。

(c) 改 `respond(requestId:accept:)`：

```swift
func respond(requestId: Int, accept: Bool) async {
    guard let token = tokenProvider() else {
        return
    }

    do {
        _ = try await requestRepo.respond(id: requestId, accept: accept, token: token)
        if accept {
            haptics.success()
        } else {
            haptics.warning()
        }
        await refresh()
    } catch {
        errorMessage = String(describing: error)
    }
}
```

> 触觉只在 `try` 不抛错的成功路径触发；catch 里**不**触发任何反馈（不变式 3）。

- [x] **Step 6: 跑测试，验证通过**

Run: `$TEST` 全量。

Expected: HapticFeedbackInjectionTests 4 条全过；其它既有 ChatViewModel / ContactsViewModel 测试也全过（init 默认参数对既有测试透明）。

如果出现"既有测试编译错"，多半是某个旧测试也在 `init` 后续传了 typingSender / idleTypingDuration 等位置参数 —— 因为 `haptics` 加到了参数末尾且有默认值，应该不破。如果仍破，把新 `haptics:` 参数挪到既有所有 default-valued 参数之后即可。

- [x] **Step 7: Commit**

```bash
git add ios-app/EchoIM/Core/Utilities/HapticFeedback.swift \
        ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
        ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift \
        ios-app/EchoIMTests/HapticFeedbackInjectionTests.swift
git commit -m "feat(ios): add haptic feedback for send / friend request response"
```

**Task 2 实现记录（2026-04-29）**

- 已完成：新增 `HapticFeedbackProvider`、`UIKitHapticFeedback`、`NoOpHapticFeedback`；`ChatViewModel.sendText` / `sendCompressedImage` 在 REST 成功合并后触发 `lightImpact()`；`ContactsViewModel.respond` 成功后按 accept/decline 触发 `success()` / `warning()`；新增 5 条注入点测试（含 sendText 失败不触发 haptic）。
- 验证：TDD RED 阶段定向测试按预期编译失败（缺 `HapticFeedbackProvider` 与 `haptics:` init 参数）；GREEN 后 `xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15' test -only-testing:EchoIMTests/HapticFeedbackInjectionTests` 通过，5 条测试全过；`xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15' test -only-testing:EchoIMTests -parallel-testing-enabled NO` 通过，218 tests / 48 suites 全过。
- 实现中问题：`@MainActor` 协议默认实现如果直接写成 `haptics: HapticFeedbackProvider = UIKitHapticFeedback()`，Swift 会把默认参数求值视为非隔离上下文并报错；已改为 `haptics: HapticFeedbackProvider? = nil`，在 VM 的 `@MainActor` init 内构造 `UIKitHapticFeedback()`。另外按计划原始 `$TEST` 不带 `-parallel-testing-enabled NO` 时，本机出现 `UserSessionRoutingTests.makeFixture()` 触发的测试进程崩溃，166 个用例被同一 crash 标失败；单独跑 `UserSessionRoutingTests` 通过，串行全量通过，且日志里有 SwiftData/SQLite `vnode unlinked while in use`，判断为既有 SwiftData cache 清理与并行 runner 的资源碰撞，不是 Task 2 代码回归。

---

## Task 3: StateView helper + 重构 List 全屏空/错态

**Files:**
- Create: `ios-app/EchoIM/Core/UI/StateView.swift`
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`

> `UserSearchSheetView` **不在本 Task 重构范围**——它的"至少输入两个字符 / 没有匹配的用户"是搜索框下方 inline 提示，不适合 ContentUnavailableView 全屏占位语义。该文件的中文文案在 Task 7 i18n 扫尾时改 `String(localized:)`，结构保持原样。

设计依据：spec §8 P8 "加载/空/错误态统一（spinner / empty / retry）"、不变式 5、front matter "已知妥协"第三条（包装而非替换）。

- [ ] **Step 1: 创建 StateView.swift**

Use Write 创建 `ios-app/EchoIM/Core/UI/StateView.swift`：

```swift
import SwiftUI

/// 标准化的"空/错"状态视图：iOS 17 ContentUnavailableView 包装层。
/// 仅用于"无数据 / 拉取失败"这种 List 全屏占位场景；inline / cell 内的局部空态请直接写 inline 文本。
struct StateView: View {
    enum Kind {
        case empty(title: LocalizedStringKey, systemImage: String, hint: LocalizedStringKey?)
        case error(title: LocalizedStringKey, message: String, systemImage: String, retry: (() -> Void)?)
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case let .empty(title, systemImage, hint):
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let hint {
                    Text(hint)
                }
            }
        case let .error(title, message, systemImage, retry):
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } actions: {
                if let retry {
                    Button("重试", action: retry)
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

extension StateView {
    /// 列表无数据。
    static func empty(
        title: LocalizedStringKey,
        systemImage: String,
        hint: LocalizedStringKey? = nil
    ) -> StateView {
        StateView(kind: .empty(title: title, systemImage: systemImage, hint: hint))
    }

    /// 列表加载失败 + 重试按钮。
    static func error(
        title: LocalizedStringKey = "加载失败",
        message: String,
        systemImage: String = "exclamationmark.triangle",
        retry: (() -> Void)? = nil
    ) -> StateView {
        StateView(kind: .error(title: title, message: message, systemImage: systemImage, retry: retry))
    }
}
```

> "重试" 仍写中文字面量；本地化在 Task 7 集中扫一遍。

- [ ] **Step 2: 重构 ConversationsListView 的 empty / error**

Edit `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`：

把 `emptyState` 与 `errorState(_:)` 改为：

```swift
private var emptyState: some View {
    StateView.empty(
        title: "暂无会话",
        systemImage: "bubble.left.and.bubble.right",
        hint: "从「联系人」里选一个好友开始聊天"
    )
}

private func errorState(_ message: String) -> some View {
    StateView.error(message: message) {
        Task { await vm.load() }
    }
}
```

> 删掉原 `VStack { Image; Text; Text; Button("重试") { ... } }` 实现。`accessibilityIdentifier` 不要在 StateView 内部加；如外层调用点本来就没加 a11y id（grep 一遍确认），删除前后行为等价。

- [ ] **Step 3: 重构 FriendsListView 的 emptyState**

Edit `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`：

把 `emptyState` 改为：

```swift
private var emptyState: some View {
    StateView.empty(
        title: "还没有好友",
        systemImage: "person.2",
        hint: "点右上角 + 搜索用户添加好友"
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("friendsEmpty")
}
```

> 保留 `accessibilityIdentifier("friendsEmpty")` —— 既有 `FriendRequestCrossAccountSmokeTests` 等可能依赖。

- [ ] **Step 4: 编译 + 跑 UITest 全量验证 a11y identifier 不破**

Run: `$BUILD` && `$UITEST`

Expected: build SUCCEEDED；既有 XCUITest 全部通过（包括 `LoginSmokeTests` / `ChatSmokeTests` / `FriendRequestCrossAccountSmokeTests` / `ImageSendSmokeTests` / `ClearCacheSmokeTests` / `TabNavigationSmokeTests` / `ProfileEditSmokeTests` / `UserDetailFromChatSmokeTests` / `PresenceTypingSmokeTests`）。

如果某个 test 失败，多半是它在 element tree 里查 `friendsEmpty` / `conversationsList` / `errorMessage` 这种 a11y identifier；按报错指向的 query 在 StateView 调用点补 `.accessibilityIdentifier(...)`。

- [ ] **Step 5: 跑单测全量**

Run: `$TEST`

Expected: 既有所有单测通过（StateView 是 view-only，无 VM 影响）。

- [ ] **Step 6: Commit**

```bash
git add ios-app/EchoIM/Core/UI/StateView.swift \
        ios-app/EchoIM/Features/Conversations/ConversationsListView.swift \
        ios-app/EchoIM/Features/Contacts/FriendsListView.swift
git commit -m "refactor(ios): unify list empty / error state via ContentUnavailableView wrapper"
```

---

## Task 4: 键盘处理打磨 — ChatView scrollDismiss + toolbar Done

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`

设计依据：spec §8 P8 "键盘处理（输入框上浮、滚动跟随）"、不变式 6（dismiss modifier 加在 ScrollView 而非 LazyVStack）。

最近 commit 7efea91 / afc9430 已经做了"输入框上浮 + 滚动到底锚点"的基础。本任务补两个常见 UX：用户向下滑消息列表时键盘自然下沉；以及在 toolbar 添加 `Done` 按钮主动收键盘（对左手或单手用户更友好）。

- [ ] **Step 1: 加 scrollDismissesKeyboard modifier**

Edit `ios-app/EchoIM/Features/Chat/ChatView.swift`：

定位到 `messagesList` 内部的 `ScrollView { LazyVStack { ... } }`；在 `ScrollView` 闭合花括号之后（即与 `.background(Color(uiColor: .systemBackground))` 同级）加：

```swift
.scrollDismissesKeyboard(.interactively)
```

> 加在 ScrollView 同级 modifier 链上，**不要**加在 LazyVStack 内部。位置示例（与现有代码顺序对齐）：

```swift
ScrollView {
    LazyVStack(spacing: 8) { ... }
    .padding(.horizontal, 12)
    .padding(.top, 10)
}
.background(Color(uiColor: .systemBackground))
.scrollDismissesKeyboard(.interactively)        // 新增
.contentShape(Rectangle())
.simultaneousGesture(...)
.overlay { ... }
.onChange(...) { ... }
```

- [ ] **Step 2: 加 keyboard toolbar 的"完成"按钮**

定位到 `inputBar` 之外，body 的 `.toolbar { ... }` 段（即 toolbar `principal` 同级）；新增一个 keyboard placement 的 toolbar item：

```swift
.toolbar {
    ToolbarItem(placement: .principal) {
        principalTitle
    }
    ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完成") {
            isInputFocused = false
        }
        .accessibilityIdentifier("chatKeyboardDone")
    }
}
```

> "完成" 仍写中文字面量；Task 7 本地化扫尾时改 LocalizedStringKey。`accessibilityIdentifier` 用 `chatKeyboardDone`（ASCII 常量）。

- [ ] **Step 3: 编译 + 手工验证**

Run: `$BUILD`

Expected: build SUCCEEDED。

手工验证（Simulator）：

1. 登录测试账号 → 进入任意会话
2. 点输入框 → 键盘弹起 + 输入栏上浮
3. 在消息列表上**向下滑动** → 键盘跟手指 interactively 下沉
4. 重新点输入框 → 键盘弹回
5. 看键盘上方有 "完成" 按钮（在系统键盘工具栏右侧）→ 点击 → 键盘收起

- [ ] **Step 4: 跑既有 XCUITest 验证不破**

Run: `$UITEST`

Expected: 既有 9 个 XCUITest 全部通过；尤其 `ChatSmokeTests` / `ImageSendSmokeTests` / `PresenceTypingSmokeTests` 不受 toolbar 新增影响。

- [ ] **Step 5: Commit**

```bash
git add ios-app/EchoIM/Features/Chat/ChatView.swift
git commit -m "feat(ios): polish chat keyboard — scrollDismiss interactive + toolbar Done"
```

---

## Task 5: Dark Mode 视觉审计 + 修复（按需）

**Files:**
- Audit checklist: 写入本计划末尾"Dark Mode 验收清单"节
- Modify: 视觉问题发现后按需 inline 修复

设计依据：spec §8 P8 "所有界面 Dark Mode 检查"、front matter "已知妥协"第二条（先审计、按需修）。

> **注意**：本 Task 不预先规划修复 step——从代码扫读，所有 view 都用了 system semantic color（`.systemBackground` / `.secondarySystemBackground` / `.secondary` / `.accentColor`），固定颜色仅在 Lightbox（黑底白字，故意）和 unread badge（红底白字，dark mode 下也合适）。预期视觉验收**几乎全过**。

- [ ] **Step 1: 准备 light / dark 截图清单**

每个屏幕在 Simulator 下分别截一张 light + dark：

```text
屏幕清单：
- LoginView（含字段错误状态）
- RegisterView（含字段错误状态）
- ConversationsListView（empty / loaded / error 三种状态）
- ChatView（无消息 / 有消息 / 输入态 / typing 态 / 失败重试态 / 图片消息）
- ImageMessageBubble + Lightbox（全屏图）
- ContactsView + FriendsListView（empty / loaded）
- FriendRequestsSheetView（incoming / sent / history 三段）
- UserSearchSheetView（搜索结果 / 空提示 / 已发送状态）
- UserDetailView（在线 / 离线）
- MeView（编辑资料入口 / 清除缓存确认 / 登出）
- ProfileEditView（默认 / 上传中 / 上传失败）
```

切 Dark Mode：Simulator → Features → Toggle Appearance（⌘⇧A）。

- [ ] **Step 2: 视觉走查 checklist**

每个屏幕在 light / dark 下检查：

- 文字 contrast 是否清晰（无浅灰文字在浅色背景 / 深灰文字在深色背景）
- 头像 placeholder 背景是否随系统色（灰底 → dark 自动反色）
- Badge / capsule 是否仍可读（红底白字 OK）
- 加载圆圈、错误三角、空态 icon 颜色合理
- Bubble 自己消息（accent color）+ 对方消息（secondarySystemBackground）在 dark 下区分度足够
- Lightbox 故意纯黑底，dark 下与系统融合无突兀

- [ ] **Step 3: 记录发现（如有）**

把每个屏幕的"light: ✅ / ❌ + 问题"和"dark: ✅ / ❌ + 问题"以表格形式追加到本计划末尾"Dark Mode 验收清单"节。

如**无**任何视觉问题 → 在该节写"全部通过，无需修复"。

如**有**问题 → 在本 Task 后续 Step 4 inline 加修复 step（path / code / 测试方法），并在末尾验收节标注修复 commit。

- [ ] **Step 4 (按需): 修复 + 提交**

仅当 Step 3 发现问题时存在。**修复策略**：

- 写死颜色 → 改成 `Color(uiColor: .label)` / `.secondary` 等 semantic
- 自定义颜色 → 用 `Color("CustomColor")` 在 Assets.xcassets 里加 light / dark 双值
- 局部 contrast 不够 → 调 `foregroundStyle` 或加描边

修复后再走一遍 Step 2 视觉验证；commit message 形如 `fix(ios): improve dark mode contrast in <view>`。

- [ ] **Step 5: Commit Dark Mode 验收清单（即使无修复）**

```bash
git add docs/superpowers/plans/2026-04-29-ios-p8-polish-i18n.md
git commit -m "docs(ios): record P8 dark mode visual audit results"
```

---

## Task 6: 本地化 ViewModel 错误文案

**Files:**
- Modify: `ios-app/EchoIM/Features/Auth/LoginViewModel.swift`
- Modify: `ios-app/EchoIM/Features/Auth/RegisterViewModel.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift`

设计依据：spec §8 P8 "i18n: zh / en"、不变式 1（自定义中文 → `String(localized:)`；`String(describing: error)` 透传不本地化）。

- [ ] **Step 1: 改 LoginViewModel.swift**

Edit `ios-app/EchoIM/Features/Auth/LoginViewModel.swift`：

```swift
// 原: let message = "邮箱和密码不能为空"
let message = String(localized: "邮箱和密码不能为空")

// 原: toast = "登录失败，请重试"
toast = String(localized: "登录失败，请重试")

// 原: return "邮箱或密码错误"
return String(localized: "邮箱或密码错误")

// 原: return "网络错误，请检查连接"
return String(localized: "网络错误，请检查连接")

// 原: return "登录失败，请重试"  ← 注意这是 mapError 里的，与 toast 那条文案重复 OK
return String(localized: "登录失败，请重试")
```

> Replace 时全文搜索字符串再 Edit；不要 replace_all 因为字符串可能在注释里。

- [ ] **Step 2: 改 RegisterViewModel.swift**

Edit `ios-app/EchoIM/Features/Auth/RegisterViewModel.swift`：

把以下中文字符串赋值统一改成 `String(localized:)`：

- `inviteCodeError = "邀请码不能为空"` → `inviteCodeError = String(localized: "邀请码不能为空")`
- `usernameError = "用户名至少 3 位"` → `String(localized: "用户名至少 3 位")`
- `emailError = "邮箱格式不正确"` → `String(localized: "邮箱格式不正确")`
- `passwordError = "密码至少 8 位"` → `String(localized: "密码至少 8 位")`
- `state = .failed(.fieldValidation(field: nil, message: "客户端校验未通过"))` → `... message: String(localized: "客户端校验未通过")`
- `toast = "注册失败，请重试"`（两处）→ `String(localized: "注册失败，请重试")`
- `inviteCodeError = "邀请码无效"` → `String(localized: "邀请码无效")`
- `toast = "邀请码无效"` → `String(localized: "邀请码无效")`（与上 key 同一条 catalog 项）
- `emailError = "邮箱已被注册"` → `String(localized: "邮箱已被注册")`
- `usernameError = "用户名已被占用"` → `String(localized: "用户名已被占用")`
- `toast = "网络错误，请检查连接"` → `String(localized: "网络错误，请检查连接")`

- [ ] **Step 3: 改 ContactsViewModel.swift**

Edit `ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift`：

实际看下来 ContactsViewModel 只有 `errorMessage = String(describing: error)` 的透传，**没有自定义中文字面量**。本 Step 实测可能为空 —— Read 一遍确认。

如果 grep 出 `errorMessage = "..."` 或 `_ = "中文"` 这种自定义文案，按上述模式改 `String(localized:)`；如果没有，本 Step **跳过**并在 plan 内 inline 注明"已确认无自定义中文文案需要本地化"。

- [ ] **Step 4: 编译 + 跑单测全量**

Run: `$BUILD` && `$TEST`

Expected: build SUCCEEDED；所有既有 LoginViewModel / RegisterViewModel / ContactsViewModel 测试通过——`String(localized:)` 在编译期等价于"返回 source language 字符串（zh-Hans）"，对单测的字符串相等断言透明。

如果某个测试 `#expect(vm.toast == "登录失败，请重试")` 失败，原因是 `String(localized:)` 在测试 bundle 下可能查到 en 翻译（Test bundle 默认走 host system locale）。如出现，把测试断言改成 `String(localized: "登录失败，请重试")` 即可对齐。

- [ ] **Step 5: Commit**

```bash
git add ios-app/EchoIM/Features/Auth/LoginViewModel.swift \
        ios-app/EchoIM/Features/Auth/RegisterViewModel.swift \
        ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift
git commit -m "i18n(ios): wrap viewmodel error strings in String(localized:)"
```

---

## Task 7: 本地化 View 文案（Text / Button / Section / accessibilityLabel）

**Files:**
- Modify: `ios-app/EchoIM/Features/Auth/LoginView.swift`
- Modify: `ios-app/EchoIM/Features/Auth/RegisterView.swift`
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/FriendsListView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/FriendRequestsSheetView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/UserSearchSheetView.swift`
- Modify: `ios-app/EchoIM/Features/Contacts/UserDetailView.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`
- Modify: `ios-app/EchoIM/Features/Chat/MessageBubble.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ImageMessageBubble.swift`
- Modify: `ios-app/EchoIM/Features/Chat/Lightbox.swift`
- Modify: `ios-app/EchoIM/Features/Me/MeView.swift`
- Modify: `ios-app/EchoIM/Features/Me/ProfileEditView.swift`
- Modify: `ios-app/EchoIM/Features/Main/MainTabView.swift`
- Modify: `ios-app/EchoIM/Core/UI/StateView.swift`（"重试" 文案）
- Modify: `ios-app/EchoIM/Core/UI/PresenceDot.swift`（`.accessibilityLabel("在线")` —— 用户可见的 a11y label）
- Modify: `ios-app/EchoIM/Core/Networking/Models/FriendRequest.swift`（`displayTitle(fallback: String = "用户")` —— 默认值是用户可见 fallback）

设计依据：spec §8 P8 "i18n"、不变式 2（accessibilityIdentifier 不本地化）、front matter "Strings Catalog 自动抽取机制"。

> **关键策略**：`Text("登录")` / `Button("登录") { ... }` / `Section("邮箱")` 这些位置参数本来就是 `LocalizedStringKey`。**本 Task 不改源代码字面量**——所有 `Text("...")` 现状保持中文字面量，因为 SwiftUI 已经走 LocalizedStringKey。Catalog 在 Task 1 后第一次 build 就开始自动收集这些 key。
>
> **本 Task 真正需要修的是**：
>
> 1. `accessibilityLabel("发送图片")` 这种**非 LocalizedStringKey** 的 String 参数 → 改成 `accessibilityLabel(Text("发送图片"))` 或保持，因为 `accessibilityLabel(_ titleKey: LocalizedStringKey)` 也接受 LocalizedStringKey；优先用前者。
> 2. `Text("用户\(senderId)")` 这种插值，确保 catalog 抽出的 key 是稳定的 `"用户 %lld"`。
> 3. `Text("已发送" or "添加")` 这种由 String 变量返回的位置——VM 已在 Task 6 改 `String(localized:)`，View 直接 `Text(vm.actionLabel)` 即可（Text 的 String 重载在 SwiftUI 18 起也走 LocalizedStringKey 路径，但稳妥起见这里 VM 返回的 String 已经是 localized 后的最终文案，View 端直接展示即可）。
> 4. `Alert.Button(_:role:)` / `confirmationDialog`/`alert` 的 title 与 message —— 同样接受 LocalizedStringKey，已自动走 catalog。
> 5. `Label("编辑资料", systemImage: ...)` —— `Label` 接受 LocalizedStringKey，自动走。

实际操作分文件：

- [ ] **Step 1: LoginView.swift / RegisterView.swift —— accessibilityLabel 改为 Text() 形式**

Edit `LoginView.swift` / `RegisterView.swift`：grep 一遍 `accessibilityLabel\(".*[一-龥]` 出现的位置。如果有，统一改成 `accessibilityLabel(Text("xxx"))`。

> 截至 Task 1 开始的代码扫读，Login/Register 的 accessibilityLabel 都是 ASCII（如 `"loginEmail"`）—— 这是 a11y identifier 不是 label，不归本 Task 管。如果 grep 结果为空，本 Step **跳过**并 inline 注明"已确认无中文 accessibilityLabel"。

- [ ] **Step 2: ChatView.swift —— accessibilityLabel("发送图片") / "发送" / "关闭" / "完成"**

Edit `ios-app/EchoIM/Features/Chat/ChatView.swift`：

```swift
// 原: .accessibilityLabel("发送图片")
.accessibilityLabel(Text("发送图片"))

// 原: .accessibilityLabel("发送")
.accessibilityLabel(Text("发送"))
```

`Text("正在输入...")` / `Text("加载更早消息")` / `Text("说点什么...")` 已经是 LocalizedStringKey，不需要改源码——catalog 会自动抽。

`Button("完成")`（Task 4 新加的 keyboard toolbar）已经是 LocalizedStringKey，自动走。

- [ ] **Step 3: Lightbox.swift —— accessibilityLabel("关闭")**

Edit `ios-app/EchoIM/Features/Chat/Lightbox.swift`：

```swift
// 原: .accessibilityLabel("关闭")
.accessibilityLabel(Text("关闭"))
```

- [ ] **Step 4: MessageBubble.swift / ImageMessageBubble.swift —— accessibilityIdentifier 给 bubble 加上**

Edit `ios-app/EchoIM/Features/Chat/MessageBubble.swift`：

在最外层 HStack / view 上加 `accessibilityIdentifier(...)`：

```swift
.accessibilityIdentifier("chatBubble_text_\(message.localId)")
```

> 用于 Task 9 GoldenPathSmokeTests 断言。`localId` 在 confirmed 消息上是 `id-\(message.id)` 格式（来自 ChatViewModel.mergeServerResult）。

Edit `ios-app/EchoIM/Features/Chat/ImageMessageBubble.swift`：

同样在最外层加：

```swift
.accessibilityIdentifier("chatBubble_image_\(message.localId)")
```

> 注意：`message` 是参数（`LocalMessage`）。如参数名不同按现有命名调整。

- [ ] **Step 5: FriendRequestsSheetView.swift —— "用户\(id)" 插值**

Edit `ios-app/EchoIM/Features/Contacts/FriendRequestsSheetView.swift`：

```swift
// 原: Text(request.displayTitle(fallback: "用户\(request.senderId)"))
Text(request.displayTitle(fallback: String(localized: "用户 \(request.senderId)")))

// 原: Text(request.displayTitle(fallback: "用户\(request.recipientId)"))
Text(request.displayTitle(fallback: String(localized: "用户 \(request.recipientId)")))
```

> **注意**：`String(localized: "用户 \(id)")` 编译时抽到 catalog 的 key 是 `"用户 %lld"`（`Int` → `%lld`）。en 翻译（Task 8）写 `"User %lld"`。**这是不变式 1 的关键 case**：`fallback:` 接受 String，必须用 `String(localized:)`。
>
> 中文字面量里"用户" 与 `\(id)` 之间**加一个空格**——为的是英文翻译时"User" 与数字之间也有空格，符合 English typography。实操：原代码 `"用户\(senderId)"` 没空格，改成 `"用户 \(senderId)"`（zh 多一个空格视觉无害，en 翻译则恰好正常）。

- [ ] **Step 6: ConversationsListView.swift —— "暂无消息"等 String 返回的本地化**

Edit `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`：

`previewText` 计算属性返回 String，里面有 `"[图片]"` 和 `"暂无消息"` 两个字面量：

```swift
private var previewText: String {
    if let body = conversation.lastMessageBody, !body.isEmpty {
        return body
    }
    if conversation.lastMessageType == "image" {
        return String(localized: "[图片]")
    }
    return String(localized: "暂无消息")
}
```

- [ ] **Step 7: UserSearchSheetView.swift —— "已发送" / "添加" String 返回的本地化**

Edit `ios-app/EchoIM/Features/Contacts/UserSearchSheetView.swift`：

把返回 String 的 `actionLabel`（具体函数名按代码现状）里：

```swift
// 原: return "已发送"
return String(localized: "已发送")

// 原: return "添加"
return String(localized: "添加")
```

`emptyHint("至少输入两个字符")` / `emptyHint("没有匹配的用户")` —— `emptyHint` 参数若是 `String`，改成 `String(localized: "...")`；若是 `LocalizedStringKey`，保持。**先 Read 该文件确认 `emptyHint` 签名**再决定。

- [ ] **Step 8: ProfileEditView.swift —— "上传失败：\(error)" 与 "留空将显示用户名 @\(username)"**

Edit `ios-app/EchoIM/Features/Me/ProfileEditView.swift`：

`Text("上传失败：\(error)")` 中 `error` 是 String —— 这是 view 层用 `LocalizedStringKey` 插值，catalog key 自动是 `"上传失败：%@"`。**保持源码不改**，catalog 自动抽。`error` 内容是 `String(describing: error)` 的透传，不本地化（不变式 1）。

`Text("好友看到的名字。留空将显示用户名 @\(username)。")` —— 同理，保持源码。catalog key 是 `"好友看到的名字。留空将显示用户名 @%@。"`。

- [ ] **Step 9: Core/ 层修复（PresenceDot + FriendRequest.displayTitle）**

Edit `ios-app/EchoIM/Core/UI/PresenceDot.swift`：

```swift
// 原: .accessibilityLabel("在线")
.accessibilityLabel(Text("在线"))
```

> "在线" 这条 key 与 `UserDetailView` 已经有的 `Text(isOnline ? "在线" : "离线")` 共用同一个 catalog 项，无重复。

Edit `ios-app/EchoIM/Core/Networking/Models/FriendRequest.swift`：

把：
```swift
func displayTitle(fallback: String = "用户") -> String {
```

改成：
```swift
func displayTitle(fallback: String = String(localized: "用户")) -> String {
```

> 默认值 `"用户"` 是用户可见的 fallback（联表数据缺失时显示）。改成 `String(localized:)` 让它走 catalog；`"用户"` key 与 Task 7 Step 5 `String(localized: "用户 \(senderId)")` 不冲突 —— 后者 catalog key 是 `"用户 %lld"`，前者是 `"用户"`，是两条独立条目。

> **Swift 可用性提示**：`String(localized:)` 作为函数参数默认值在 Swift 5.9+ / iOS 17+ 合法（默认值表达式不要求编译期常量）。本项目 baseline iOS 17+，没问题。

- [ ] **Step 10: 全局扫一遍确认无漏（Code Hygiene Pass）**

Run（搜索整个 ios-app/EchoIM/ 下所有 `.swift` 文件中残留的中文 String 字面量在 String 上下文出现）：

```bash
rg -nE '"[^"]*[一-龥][^"]*"' ios-app/EchoIM --glob '*.swift' \
  | grep -vE '^[^:]+:[0-9]+:\s*//' \
  | grep -vE 'String\(localized:' \
  | grep -vE 'accessibilityIdentifier'
```

Expected: 命中行**全部**是 SwiftUI Text/Button/Section/Label 等接受 `LocalizedStringKey` 的位置（catalog 自动抽取无需手改），或注释。如果出现"作为 String 参数传入但未包 String(localized:)"的位置，按 Step 1-9 的模式补包。

> 之所以要做这一步：Step 1-8 是按已知文件列表逐个改，这一步是兜底——保证没有任何"用户可见中文"被遗漏。

- [ ] **Step 11: 编译，验证 catalog 自动收集 key**

Run: `$BUILD`

Expected: build SUCCEEDED。Build 后查看 catalog：

```bash
python3 -c "import json; data = json.load(open('ios-app/EchoIM/Localizable.xcstrings')); print(len(data['strings']), 'keys'); print(sorted(data['strings'].keys())[:20])"
```

Expected: `keys` 数量 ≥ 80（约 100 条；具体数依视图字面量精确数）。前 20 条 key 包含 `"登录"` / `"注册"` / `"我"` / `"暂无会话"` 等。

如果 catalog `strings` 仍为空 —— 最常见原因是 Xcode build 没真触发 swift 编译（cache 命中）。clean 后重 build：

```bash
xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  clean build
```

- [ ] **Step 12: 跑单测 + UITest 全量**

Run: `$TEST` && `$UITEST`

Expected: 全部通过。`accessibilityLabel(Text("发送图片"))` 与原 `accessibilityLabel("发送图片")` 在 a11y tree 上等价，UITest 不破。

- [ ] **Step 13: Commit**

```bash
git add ios-app/EchoIM/Localizable.xcstrings \
        ios-app/EchoIM/Features/ \
        ios-app/EchoIM/Core/UI/StateView.swift
git commit -m "i18n(ios): localize all view-layer strings via Strings Catalog auto-extraction"
```

---

## Task 8: Strings Catalog 补 en 翻译

**Files:**
- Modify: `ios-app/EchoIM/Localizable.xcstrings`

设计依据：spec §8 P8 "i18n: zh / en"、front matter "Strings Catalog 操作速查"。

本 Task 是文案翻译工作；产出物是 catalog 内每个 key 的 en localization 都从 `state: "new"` 变成 `state: "translated"`。

- [ ] **Step 1: 用对照表批量填 en 翻译**

`Localizable.xcstrings` 是 JSON，可以编辑器直接改。对每个 zh-Hans key，在 `localizations` 下加 `en` 子树：

```json
"登录" : {
    "localizations" : {
        "en" : {
            "stringUnit" : {
                "state" : "translated",
                "value" : "Sign In"
            }
        }
    }
}
```

完整对照表（按出现频率与逻辑分组）：

**Auth：**
| zh-Hans key | en value |
|---|---|
| 登录 | Sign In |
| 注册 | Sign Up |
| 邮箱 | Email |
| 密码 | Password |
| 至少 8 位 | At least 8 characters |
| 没有账号？去注册 | Don't have an account? Sign up |
| 已有账号？返回登录 | Already have an account? Sign in |
| 登录失败 | Sign in failed |
| 注册失败 | Sign up failed |
| 好 | OK |
| 邀请码 | Invite Code |
| 用户名 | Username |
| 邮箱和密码不能为空 | Email and password are required |
| 登录失败，请重试 | Sign in failed. Please try again. |
| 邮箱或密码错误 | Incorrect email or password |
| 网络错误，请检查连接 | Network error. Please check your connection. |
| 邀请码不能为空 | Invite code is required |
| 用户名至少 3 位 | Username must be at least 3 characters |
| 邮箱格式不正确 | Invalid email format |
| 密码至少 8 位 | Password must be at least 8 characters |
| 客户端校验未通过 | Client-side validation failed |
| 注册失败，请重试 | Sign up failed. Please try again. |
| 邀请码无效 | Invalid invite code |
| 邮箱已被注册 | Email is already registered |
| 用户名已被占用 | Username is already taken |
| you@example.com | you@example.com |

**Tab / 导航：**
| zh-Hans key | en value |
|---|---|
| 聊天 | Chats |
| 联系人 | Contacts |
| 我 | Me |
| 资料 | Profile |
| 编辑资料 | Edit Profile |

**会话列表：**
| zh-Hans key | en value |
|---|---|
| 暂无会话 | No conversations |
| 从「联系人」里选一个好友开始聊天 | Pick a friend from "Contacts" to start chatting |
| 加载失败 | Failed to load |
| 重试 | Retry |
| [图片] | [Image] |
| 暂无消息 | No messages yet |

**联系人：**
| zh-Hans key | en value |
|---|---|
| 还没有好友 | No friends yet |
| 点右上角 + 搜索用户添加好友 | Tap + in the top right to search and add friends |
| 添加好友 | Add Friend |
| 输入用户名搜索 | Search by username |
| 至少输入两个字符 | Type at least 2 characters |
| 没有匹配的用户 | No users match |
| 已发送 | Sent |
| 添加 | Add |
| 关闭 | Close |
| 好友申请 | Friend Requests |
| 待处理 | Pending |
| 历史 | History |
| 同意 | Accept |
| 拒绝 | Decline |
| 等待接受 | Waiting for response |
| 已接受 | Accepted |
| 已拒绝 | Declined |
| 发送 | Sent |
| 收到 | Received |
| 暂无好友申请 | No friend requests |
| 用户 | User |
| 用户 %lld | User %lld |
| 在线 | Online |
| 离线 | Offline |
| 发送失败 | Failed to send |

**聊天：**
| zh-Hans key | en value |
|---|---|
| 正在输入... | Typing... |
| 加载更早消息 | Load earlier messages |
| 说点什么... | Say something... |
| 发送中... | Sending... |
| 发送图片 | Send image |
| 完成 | Done |

**Me：**
| zh-Hans key | en value |
|---|---|
| 头像 | Avatar |
| 显示名称 | Display Name |
| 保存 | Save |
| 上传中… | Uploading… |
| 更换头像 | Change Avatar |
| 上传失败：%@ | Upload failed: %@ |
| 保存失败 | Save failed |
| 知道了 | Got it |
| JPEG / PNG / HEIC，自动压缩为 400×400 | JPEG / PNG / HEIC, auto-cropped to 400×400 |
| 从相册选择一张图片，自动裁剪为 400×400 头像。 | Pick a photo. It will be cropped to a 400×400 avatar. |
| 好友看到的名字。留空将显示用户名 @%@。 | The name your friends see. Leave empty to show @%@. |
| 清除聊天缓存 | Clear chat cache |
| 登出 | Sign Out |
| 清除本地聊天缓存？ | Clear local chat cache? |
| 清除 | Clear |
| 取消 | Cancel |
| 将删除本设备上缓存的消息与图片。服务器上的消息不受影响。 | This removes cached messages and images on this device. Server data is unaffected. |
| 清除中… | Clearing… |

> 如果实际 catalog 收集到的 key 不止上面这些（例如某条文案我漏写），按相同语义补 en 翻译，并把新条目追加到本 plan 的对照表（让计划文档与 catalog 同步）。

- [ ] **Step 2: 验证 catalog 状态**

```bash
python3 -c "
import json
data = json.load(open('ios-app/EchoIM/Localizable.xcstrings'))
total = len(data['strings'])
translated = sum(1 for k, v in data['strings'].items()
                 if v.get('localizations', {}).get('en', {}).get('stringUnit', {}).get('state') == 'translated')
new_state = sum(1 for k, v in data['strings'].items()
                if v.get('localizations', {}).get('en', {}).get('stringUnit', {}).get('state') in ('new', None))
stale = sum(1 for k, v in data['strings'].items()
            if v.get('extractionState') == 'stale')
print(f'total={total}, en_translated={translated}, en_new={new_state}, stale={stale}')
"
```

Expected: `en_translated == total`，`en_new == 0`，`stale == 0`。如有 stale，删 catalog 里那条 key（源码已不再用）。

- [ ] **Step 3: 编译 + 切英文 Locale 跑既有 UITest 一次**

Run: `$BUILD`

Expected: build SUCCEEDED。

切 Simulator system language 到英文：Settings → General → Language & Region → iPhone Language → English。或在 launchArguments 加 `-AppleLanguages "(en)"` 让单次 launch 切到英文 —— 这样不影响其他 test：

跑一个 smoke 验证英文显示：

```bash
xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMUITests/LoginSmokeTests
```

Expected: `LoginSmokeTests` 仍通过 —— 它依赖 `loginEmail` / `loginPassword` / `loginSubmit` 这些 a11y identifier，不受语言切换影响。

手工验证（可选）：在 Simulator 切英文跑一遍登录 / 聊天页 / Me 页，确认显示英文文案。

- [ ] **Step 4: Commit**

```bash
git add ios-app/EchoIM/Localizable.xcstrings docs/superpowers/plans/2026-04-29-ios-p8-polish-i18n.md
git commit -m "i18n(ios): add english translations to Strings Catalog"
```

---

## Task 9: Golden path XCUITest — 登录 → 发文字 → 打开图片 picker

**Files:**
- Create: `ios-app/EchoIMUITests/GoldenPathSmokeTests.swift`

设计依据：spec §8 P8 "XCUITest golden path：登录 → 会话列表 → 发文字 → 发图片"、Task 7 加的 `chatBubble_text_*` accessibility identifier、front matter "已知妥协" 关于"发图片只到 picker 弹起"的说明。

**覆盖范围**：
- 文字消息：端到端断言（输入 → 点 send → `chatBubble_text_*` 出现）
- 图片消息：到 picker 弹起 + 关闭即停（与 `ImageSendSmokeTests` 深度一致；不依赖 simctl addmedia）

> Task 7 Step 4 同时给 `MessageBubble` 与 `ImageMessageBubble` 都加了 a11y identifier，是为未来一旦补 simctl addmedia 自动化时即用即得。本 Task 不依赖 `chatBubble_image_*` 断言。

- [ ] **Step 1: 写测试 — 端到端 golden path**

Use Write 创建 `ios-app/EchoIMUITests/GoldenPathSmokeTests.swift`：

```swift
import XCTest

/// 设计 §8 P8 golden path：登录 → 会话列表 → 进入聊天 → 发文字（断言 bubble 出现）→ 打开图片 picker（断言可打开并返回聊天页）。
/// 与 ImageSendSmokeTests 的差异：本测试额外断言文字消息 bubble 真正落到列表。
final class GoldenPathSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoldenPath_LoginSendTextAndImage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        // 登录
        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("password123")
        app.buttons["loginSubmit"].tap()

        // 进首页 + 会话列表
        let tabView = app.otherElements["mainTabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10))
        let conversationsList = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(conversationsList.waitForExistence(timeout: 10))

        // 进入第一个会话
        let firstRow = conversationsList.descendants(matching: .cell).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        // 发文字
        let input = app.textFields["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        let textBody = "p8-smoke-\(Int(Date().timeIntervalSince1970))"
        input.typeText(textBody)
        app.buttons["chatSend"].tap()

        // 断言：文字 bubble 出现（按 localId 前缀匹配，因 server-confirmed bubble localId 是 "id-<int>"）
        let textBubblePredicate = NSPredicate(format: "identifier BEGINSWITH 'chatBubble_text_'")
        let textBubble = app.descendants(matching: .any).matching(textBubblePredicate).firstMatch
        XCTAssertTrue(textBubble.waitForExistence(timeout: 10),
                      "Expected at least one chatBubble_text_* element after sending text")

        // 发图片（picker 弹起；模拟器上无相册图，跑到 picker 出现就算 golden path 覆盖）
        let picker = app.buttons["chatImagePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        // PhotosPicker 在 Simulator 上展现的 sheet（系统视图，跨 process），
        // 等待 1s 让 sheet 打开后用 swipe down 关闭，断言回到聊天页。
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
        app.swipeDown(velocity: .fast)

        // 关闭 picker 后聊天页仍在
        XCTAssertTrue(input.waitForExistence(timeout: 5))
    }
}
```

> 模拟器上发真实图片需要预置相册图（`xcrun simctl addmedia` 预先注入）。本 golden path 走到 picker 弹出 + 关闭即认为图片发送链路 UI 完备；图片消息的"上传 → message bubble 出现"端到端在 Task 5/Task 7 手工验证。本测试覆盖范围与 spec §8 P8 字面要求"发图片"对齐——picker 能弹是发图片操作的 UI 入口。
>
> 如果项目已经有"测试种子图片"机制（grep 一遍 `simctl addmedia` 或 `XCUIScreenshot.attachment`），扩展本测试到完整发图也可以；不强求。

- [ ] **Step 2: 跑测试**

Run:
```bash
xcodebuild -project ios-app/EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMUITests/GoldenPathSmokeTests
```

Expected: PASS。

如果 `chatBubble_text_*` 没找到 —— 检查 Task 7 Step 4 是否真的把 `accessibilityIdentifier("chatBubble_text_\(message.localId)")` 加到 `MessageBubble` 最外层（参考"实现说明"对 LocalMessage 字段名 `localId` 的兼容处理）。

如果 `firstRow.tap()` 之后未进入聊天页 —— 测试账号 `smoke@test.local` 可能没有任何会话；本测试依赖测试种子数据。检查 `e2e/` 或 `server/tests/` 里的 seed 流程是否在跑前已生成至少一个会话。如未，写一个先决条件检查：用 `XCTSkipIf(conversationsList.descendants(matching: .cell).count == 0, "no seed conversations")`。

- [ ] **Step 3: 跑全量 UITest 验证不破**

Run: `$UITEST`

Expected: 既有 9 个 + 新增 1 个共 10 个 XCUITest 全部通过（如果 GoldenPathSmokeTests 因 seed 数据被 skip，是 9 通过 + 1 skipped，也算通过）。

- [ ] **Step 4: Commit**

```bash
git add ios-app/EchoIMUITests/GoldenPathSmokeTests.swift
git commit -m "test(ios): add golden path UITest — login + send text + open photo picker"
```

---

## Task 10: 内存泄漏检查清单（Instruments 手工验收）

**Files:**
- Document: 本计划末尾"内存泄漏验收"节

设计依据：spec §8 P8 "内存泄漏检查（Instruments）"、front matter "已知妥协"第六条（不写 XCTest 自动化）。

- [ ] **Step 1: 准备 Allocations profiling 环境**

1. Xcode → Product → Profile（⌘I）→ 选 `Allocations` template
2. Run on Simulator iPhone 15
3. Record 启动后让 App 待机 5 秒 → 标记 generation A

- [ ] **Step 2: 场景 A — 聊天页反复进出（subscription / detach 路径）**

操作：

1. 登录
2. 在 Allocations 标记 generation B
3. 反复执行：会话列表点入聊天 → 等 1 秒 → back → 等 1 秒。重复 20 次。
4. 标记 generation C
5. 等 5 秒让 ARC 清理稳定
6. 标记 generation D

验收：

- generation B → C 净增对象数应该有合理增量（每次进出会有少量 transient 对象）
- generation C → D 后清理不再增长（D 与 C 接近）
- 反复进出 20 次的总 Persistent Bytes 增量 < 5 MB

- [ ] **Step 3: 场景 B — logout / login 切换（UserSession 释放）**

操作：

1. 在 Allocations 重新 record（清生成）
2. 反复：Me 页登出 → LoginView 登录 → 等首页加载完。重复 5 次。
3. 标记 generation E
4. 等 5 秒
5. 标记 generation F

验收：

- F 与 E 接近（UserSession + ModelContainer 应被释放）
- 没有 `EchoIM.UserSession` / `EchoIM.WebSocketClient` 类型的 Persistent 实例 > 5 个（5 次切换最多保留当前 1 个）

- [ ] **Step 4: 场景 C — 图片上传重试（ImageSendStage / Data 持有）**

操作：

1. 进入聊天页
2. 选大图发送 → 在 server 离线状态下失败
3. 点击 retry → 重新触发上传
4. 重复"选图发送 → 失败 → retry"5 次
5. 标记 generation G
6. 等 10 秒（让 imageSendStages dict 清理 + Data buffer 释放）
7. 标记 generation H

验收：

- H 与 G 接近（失败的 LocalMessage 与 imageSendStages 条目应在 retry 成功 / 用户切走聊天页 / VM detach 时清理）
- 5 次重试结束后没有 5 份大 Data buffer 同时驻留

- [ ] **Step 5: 把验收结果记进本计划末尾"内存泄漏验收"节**

格式：

```markdown
## 内存泄漏验收（Task 10 实测）

- 场景 A（聊天页反复进出 20 次）：generation B/C/D 增量分别 X / Y / Z；判定：通过 / 异常
- 场景 B（logout/login 5 次）：UserSession 残留 N 个；判定：通过 / 异常
- 场景 C（图片重试 5 次）：Data buffer 残留 M MB；判定：通过 / 异常

未观察到明显泄漏 / 观察到 [...] 已开 issue [...]
```

- [ ] **Step 6: Commit 验收记录**

```bash
git add docs/superpowers/plans/2026-04-29-ios-p8-polish-i18n.md
git commit -m "docs(ios): record P8 instruments memory leak audit results"
```

---

## Task 11: P8 收尾验收 + 提交

**Files:**
- Modify: `docs/superpowers/plans/2026-04-29-ios-p8-polish-i18n.md`（标记 checkbox）
- Modify: `tasks.md`（如需）
- Modify: `prd.md`（如需）

- [ ] **Step 1: 跑全量单测**

Run: `$TEST`

Expected: 全部通过；spec §8 P8 列出的 4 项单测在前序阶段实现的测试在本阶段改动后仍通过：
- ChatViewModelCacheTests（gap detection 三场景）
- ImageSendStageTests（重试跳过）
- ReconnectPolicyTests（退避序列）
- WSEventDecodingTests（事件 decode）
- 新增 HapticFeedbackInjectionTests 4 条

把"X tests passed, 0 failed"实际数字记进本 Step。

- [ ] **Step 2: 跑全量 XCUITest**

Run: `$UITEST`

Expected: 既有 9 个 + 新增 1 个共 10 个全部通过（或 9 通过 + 1 skipped 如 Task 9 Step 2 所述）。

- [ ] **Step 3: 实机自测脚本（手工跑一遍）**

打开 EchoIM iOS App，按以下顺序操作并观察：

1. **Dark Mode 切换**：System Settings → Display → Dark；登录页 / 聊天页 / Me 页都应正常显示，无白底黑字 / 黑底黑字反差异常
2. **触觉反馈：发文字消息**：在聊天页发一条 → 真机能感受到 light impact
3. **触觉反馈：接受好友请求**：让对方账号发好友请求，本端在好友申请页 → 同意 → success notification 振动
4. **触觉反馈：拒绝好友请求**：另一条好友请求 → 拒绝 → warning notification 振动（与 success 触感不同）
5. **键盘交互**：聊天页点输入框 → 键盘弹起；下滑消息列表 → 键盘 interactive 跟手指下沉；点 keyboard toolbar 上的 "完成" → 键盘收起
6. **i18n 切英文**：System Settings → General → Language & Region → English → 重启 App → 各页面应显示对应英文（参考 Task 8 对照表）
7. **空态展示**：注册新账号（无好友 / 无会话）→ 联系人页"还没有好友" + 会话页"暂无会话" + "重试"等都是 ContentUnavailableView 风格
8. **错误态展示**：断网 → 拉会话列表 → 显示 ContentUnavailableView 加载失败 + 重试按钮
9. **Golden path（自动化口径）**：登录 → 会话点入 → 发文字并看到文字 bubble → 打开图片 picker → 关闭后仍停留聊天页

把异常项记录到本计划末尾的"实机偏差"节。

- [ ] **Step 4: 把本计划 Task 1-11 的 checkbox 改为 `[x]`**

直接编辑 `docs/superpowers/plans/2026-04-29-ios-p8-polish-i18n.md` 顶部的 Task 标题与 Step 复选框；如有与计划不符的实现，在该 Task 末尾用一段引用注明"实际偏差"。

- [ ] **Step 5: 更新 tasks.md / prd.md 状态（如需）**

Read `tasks.md`，找 iOS P8 / 客户端打磨 / i18n 相关条目，标记完成。

如 prd.md 的 iOS 客户端章节描述与现状不符（如仍写"iOS 客户端处于脚手架阶段"），更新为"iOS 客户端 12 阶段全部完成"或类似。

- [ ] **Step 6: 最终提交**

```bash
git add docs/superpowers/plans/2026-04-29-ios-p8-polish-i18n.md tasks.md prd.md
git commit -m "docs(ios): mark P8 plan fully implemented"
```

---

## 依赖关系（与设计 §8 一致）

```
P1 (脚手架+登录) ─┐
P2 (好友+会话)   │
P3 (文字+WS)     ├─→ P8 (打磨+i18n+触觉+Dark+测试) [本阶段]
P4 (SwiftData)   │
P5 (图片消息)    │
P6 (Presence)    │
P7 (Profile)     ┘
```

P8 是横向打磨阶段，对所有前序阶段的成果做最后一轮一致性 / 国际化 / 验收。无下游阶段。

---

## 上下文索引（实现时常用的"看一眼就知道为啥这么写"的位置）

- 服务端无契约改动（P8 不改 server）：spec §8 P8 / 本计划 front matter "服务端契约改动"
- iOS 既有 ChatViewModel.sendText / sendImage 流程（Task 2 注入点）：`ios-app/EchoIM/Features/Chat/ChatViewModel.swift:240-326`
- iOS 既有 ContactsViewModel.respond（Task 2 注入点）：`ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift:66-77`
- iOS 既有 ConversationsListView empty/error（Task 3 重构起点）：`ios-app/EchoIM/Features/Conversations/ConversationsListView.swift:124-155`
- iOS 既有 ChatView ScrollView 与 inputBar（Task 4 修改起点）：`ios-app/EchoIM/Features/Chat/ChatView.swift:113-174,185-233`
- iOS 既有 PresenceTypingSmokeTests + ImageSendSmokeTests（Task 9 参考骨架）：`ios-app/EchoIMUITests/PresenceTypingSmokeTests.swift` / `ImageSendSmokeTests.swift`
- spec §8 P8 deliverable 列表：`docs/superpowers/specs/2026-04-17-ios-app-design.md:850-866`
- P7 plan 收尾结构（Task 10/11 模板）：`docs/superpowers/plans/2026-04-28-ios-p7-profile-avatar.md:2050-2120`
- 现有 4 项 spec 测试的位置（front matter "现有测试覆盖声明"）：`ios-app/EchoIMTests/ChatViewModelCacheTests.swift` / `ImageSendStageTests.swift` / `ReconnectPolicyTests.swift` / `WSEventDecodingTests.swift`

---

## Dark Mode 验收清单

> 由 Task 5 Step 3 填写。

| 屏幕 | Light | Dark | 备注 |
|---|---|---|---|
| LoginView | TBD | TBD | TBD |
| RegisterView | TBD | TBD | TBD |
| ConversationsListView (empty) | TBD | TBD | TBD |
| ConversationsListView (loaded) | TBD | TBD | TBD |
| ConversationsListView (error) | TBD | TBD | TBD |
| ChatView (no messages) | TBD | TBD | TBD |
| ChatView (with messages) | TBD | TBD | TBD |
| ChatView (typing) | TBD | TBD | TBD |
| ChatView (failed retry) | TBD | TBD | TBD |
| ImageMessageBubble | TBD | TBD | TBD |
| Lightbox | TBD | TBD | TBD |
| ContactsView (loaded) | TBD | TBD | TBD |
| FriendsListView (empty) | TBD | TBD | TBD |
| FriendRequestsSheetView | TBD | TBD | TBD |
| UserSearchSheetView | TBD | TBD | TBD |
| UserDetailView (online) | TBD | TBD | TBD |
| UserDetailView (offline) | TBD | TBD | TBD |
| MeView | TBD | TBD | TBD |
| ProfileEditView (default) | TBD | TBD | TBD |
| ProfileEditView (uploading) | TBD | TBD | TBD |
| ProfileEditView (upload failed) | TBD | TBD | TBD |

---

## 内存泄漏验收

> 由 Task 10 Step 5 填写。

- 场景 A（聊天页反复进出 20 次）：TBD
- 场景 B（logout/login 5 次）：TBD
- 场景 C（图片重试 5 次）：TBD

结论：TBD

---

## 实机偏差

> 由 Task 11 Step 3 / 各 Task 末尾填写实现与计划不符之处。
