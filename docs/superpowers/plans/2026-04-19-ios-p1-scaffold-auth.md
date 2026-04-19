# iOS P1 实施计划：工程脚手架 + 登录 / 注册

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从空壳脚手架推进到"能注册登录、能看到占位首页、能登出"的首个垂直切片（对应设计文档第 8 节 P1）。

**Architecture:** SwiftUI + MVVM + `@Observable`（iOS 17+）；Repository 抽象；手写 DI 容器 `AppContainer`；JWT 存 Keychain；REST 走 `URLSession` + `async/await`。暂不涉及 WebSocket / SwiftData / UserSession（P3 / P4 引入）。

**Tech Stack:** SwiftUI、Swift Concurrency、URLSession、KeychainAccess（SPM）、Nuke + NukeUI（SPM，本阶段仅引入以备 P2 头像使用）、Swift Testing、XCUITest。

**TDD 适用范围（重要）：** 本计划严格区分：
- **纯逻辑 → TDD**：`APIClient` JSON 解码 / `APIError` 映射 / `AuthRepository` 错误码映射 / ViewModel 的输入校验 & 错误分派。先写 Swift Testing 失败用例再补实现。
- **View / 集成 → 编译 + 模拟器手工清单**：`LoginView` / `RegisterView` / `RootView` 不写 SwiftUI 单测。验证方式是：`xcodebuild build` 保证编译通过 + 模拟器跑一遍明确的交互清单 + 关键流程的 XCUITest smoke。
- 不要试图用快照测试 / ViewInspector 等去"测视图"，超出 P1 价值范围。

**服务端依赖：** 本阶段用到的接口已在 `server/src/routes/auth.ts` 存在：`POST /api/auth/login`、`POST /api/auth/register`。后续阶段的服务端改造见"未来阶段的依赖锚点"。

---

## 开发环境前提

动工前确认：
- Xcode 26+ 已安装且能打开 `ios-app/EchoIM.xcodeproj`
- 后端能在本机跑（`docker compose up` 或 `npm --prefix server run dev`）；默认 `http://localhost:3000`
- 模拟器选择 iPhone 15（或任意 iOS 17+ 设备），**不要**选 iPad
- 已有至少一个测试用户（可用 `POST /api/auth/register` 提前建）

**约定命令**（后文直接引用）：

```bash
# 编译（Debug）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug build

# 单测
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test

# UI 测
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:EchoIMUITests test
```

记为 `$BUILD` / `$TEST` / `$UITEST`。

---

## 文件结构（P1 范围）

本阶段创建的**全部**文件（P2-P8 范围的文件不在本阶段创建）：

```
ios-app/EchoIM/
├── EchoIMApp.swift                  // 修改：用 RootView 替换 ContentView（Xcode 创建的默认位置，不移动）
├── ContentView.swift                // 删除（RootView 取代）
├── App/
│   ├── AppContainer.swift           // 新建：最小 DI（tokenStore + apiClient + currentUser）
│   └── RootView.swift               // 新建：根据登录态切换 Auth / Home
├── Core/
│   ├── Networking/
│   │   ├── APIClient.swift          // 新建：URLSession + async/await + JSON 解码
│   │   ├── APIError.swift           // 新建：network / http(status, body) / decoding / unauthorized
│   │   └── Endpoints.swift          // 新建：baseURL 构造 + login / register path
│   └── Storage/
│       └── KeychainTokenStore.swift // 新建：save / load / delete
└── Features/
    ├── Auth/
    │   ├── AuthRepository.swift     // 新建：protocol + Impl + 结构化错误映射
    │   ├── LoginViewModel.swift     // 新建：@Observable @MainActor
    │   ├── LoginView.swift          // 新建
    │   ├── RegisterViewModel.swift  // 新建
    │   └── RegisterView.swift       // 新建
    └── Home/
        └── HomePlaceholderView.swift // 新建：占位首页（用户名 + 登出）

ios-app/EchoIMTests/                  // 新建测试 target
├── MockURLProtocol.swift            // URLSession 拦截器，供 AuthRepository happy-path 测试用
├── APIErrorTests.swift
├── APIClientTests.swift
├── KeychainTokenStoreTests.swift
├── AuthRepositoryTests.swift        // 错误映射（纯函数）
├── AuthRepositoryHTTPTests.swift    // 新增：happy-path（endpoint / body / token 存储）
├── AppContainerTests.swift          // 新增：bootstrap / logout 清 Keychain
├── LoginViewModelTests.swift
└── RegisterViewModelTests.swift

ios-app/EchoIMUITests/                // 新建 UI 测试 target
└── LoginSmokeTests.swift
```

---

## Task 1：修正部署目标 + 添加测试 target

**Files:**
- Modify: `ios-app/EchoIM.xcodeproj/project.pbxproj`（手动或通过 Xcode UI）

**背景：** 当前 `project.pbxproj:181` 的 `IPHONEOS_DEPLOYMENT_TARGET = 26.0`（Xcode 26 默认值），与设计文档"iOS 17+"不符，会把所有没升级到 iOS 26 的设备排除掉。

- [ ] **Step 1：调低部署目标到 17.0**

用 Xcode UI 打开 `ios-app/EchoIM.xcodeproj` → 选中 project → Build Settings → 搜 `iOS Deployment Target` → Debug / Release 都改为 `17.0`。或直接编辑 `project.pbxproj` 把两处 `IPHONEOS_DEPLOYMENT_TARGET = 26.0;` 改成 `IPHONEOS_DEPLOYMENT_TARGET = 17.0;`。

**Verification：** 

```bash
grep IPHONEOS_DEPLOYMENT_TARGET ios-app/EchoIM.xcodeproj/project.pbxproj
```

预期输出：两行都是 `17.0`，不再出现 `26.0`。

- [ ] **Step 2：新建 EchoIMTests（Swift Testing）target**

Xcode → File → New → Target → iOS → **Unit Testing Bundle** → Product Name `EchoIMTests` → Testing System 选 **Swift Testing**（不是 XCTest）→ Target to be Tested `EchoIM`。接受默认 bundle id。

- [ ] **Step 3：新建 EchoIMUITests target**

Xcode → File → New → Target → iOS → **UI Testing Bundle** → Product Name `EchoIMUITests` → Target to be Tested `EchoIM`。

- [ ] **Step 4：验证 target 添加成功**

```bash
grep -E 'EchoIMTests|EchoIMUITests' ios-app/EchoIM.xcodeproj/project.pbxproj | head -20
```

预期：能看到两个 target 的 `PBXNativeTarget`、`productType = "com.apple.product-type.bundle.unit-test"` / `"com.apple.product-type.bundle.ui-testing"`。

- [ ] **Step 5：确认 Tests target 的部署目标也是 17.0**

Xcode 默认新建的测试 target 会继承项目 deployment target，但要确认——选中 `EchoIMTests` / `EchoIMUITests` → Build Settings → iOS Deployment Target → 17.0。

- [ ] **Step 6：冒烟编译 + 空测试**

```bash
$BUILD
$TEST
```

预期：`BUILD SUCCEEDED`，`Test Suite 'All tests' passed`（空测试通过）。

- [ ] **Step 7：提交**

```bash
git add ios-app/EchoIM.xcodeproj/project.pbxproj
git commit -m "build(ios): lower deployment target to iOS 17 and add test targets"
```

---

## Task 2：引入 SPM 依赖（KeychainAccess / Nuke / NukeUI）

**Files:**
- Modify: `ios-app/EchoIM.xcodeproj/project.pbxproj`（通过 Xcode UI 添加 Package Dependency）

Nuke / NukeUI 在 P1 不使用，但顺手引入避免 P2 再改工程文件。

- [ ] **Step 1：添加 KeychainAccess**

Xcode → File → Add Package Dependencies → URL `https://github.com/kishikawakatsumi/KeychainAccess` → 选最新稳定版（`4.2.2`+）→ 加入 `EchoIM` target。

- [ ] **Step 2：添加 Nuke（含 NukeUI）**

同样流程：URL `https://github.com/kean/Nuke` → 最新稳定版（`12.x`）→ 勾选 `Nuke` 和 `NukeUI` 两个 library，都加入 `EchoIM` target。

- [ ] **Step 3：验证 Package.resolved 记录了依赖**

```bash
cat ios-app/EchoIM.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

预期：能看到 `KeychainAccess` 和 `Nuke` 两条 `pins` 条目。如果文件不在该路径，`find ios-app -name Package.resolved`。

- [ ] **Step 4：在 EchoIMApp.swift 加 `import` 验证链接**

```swift
// ios-app/EchoIM/EchoIMApp.swift 顶部临时加：
import KeychainAccess
import Nuke
import NukeUI
```

- [ ] **Step 5：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。确认链接通了后**移除 import**（后续由真正使用的文件引入），再次 `$BUILD` 通过。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM.xcodeproj/
git commit -m "build(ios): add KeychainAccess, Nuke, NukeUI via SPM"
```

---

## Task 3：APIError 类型

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/APIError.swift`
- Test: `ios-app/EchoIMTests/APIErrorTests.swift`

- [ ] **Step 1：写失败用例**

`ios-app/EchoIMTests/APIErrorTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("APIError")
struct APIErrorTests {
    @Test func unauthorizedFrom401() {
        let err = APIError.fromStatus(401, body: Data())
        if case .unauthorized = err { return }
        Issue.record("expected .unauthorized, got \(err)")
    }

    @Test func httpCarriesStatusAndBody() {
        let body = Data("oops".utf8)
        let err = APIError.fromStatus(500, body: body)
        if case .http(let status, let b) = err {
            #expect(status == 500)
            #expect(b == body)
        } else {
            Issue.record("expected .http, got \(err)")
        }
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：编译失败，`APIError` 未定义。

- [ ] **Step 3：实现 APIError**

`ios-app/EchoIM/Core/Networking/APIError.swift`：

```swift
import Foundation

enum APIError: Error, Equatable {
    case network(URLError)
    case unauthorized
    case http(status: Int, body: Data)
    case decoding(String)
    case invalidResponse

    static func fromStatus(_ status: Int, body: Data) -> APIError {
        if status == 401 { return .unauthorized }
        return .http(status: status, body: body)
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let a), .network(let b)): return a.code == b.code
        case (.unauthorized, .unauthorized): return true
        case (.http(let sa, let ba), .http(let sb, let bb)): return sa == sb && ba == bb
        case (.decoding(let a), .decoding(let b)): return a == b
        case (.invalidResponse, .invalidResponse): return true
        default: return false
        }
    }
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
$TEST
```

预期：两个测试全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Core/Networking/APIError.swift \
        ios-app/EchoIMTests/APIErrorTests.swift
git commit -m "feat(ios): add APIError with status mapping"
```

---

## Task 4：Endpoints（baseURL + 路径）

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/Endpoints.swift`

设计：baseURL 来自 `Info.plist` 的 `EchoIMBaseURL` 键，读不到则 fallback 到 `http://localhost:3000`（模拟器）。这样 Release / TestFlight 可以换服务器，Debug 默认走本机。

- [ ] **Step 1：实现 Endpoints**

`ios-app/EchoIM/Core/Networking/Endpoints.swift`：

```swift
import Foundation

enum Endpoints {
    static let baseURL: URL = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "EchoIMBaseURL") as? String,
           let url = URL(string: s) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }()

    static func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    enum Auth {
        static let login = "api/auth/login"
        static let register = "api/auth/register"
    }
}
```

- [ ] **Step 2：在 `Info.plist` 加 `EchoIMBaseURL` 默认值（可选）+ App Transport Security**

`http://localhost:3000` 是 HTTP，iOS 默认不允许明文。在 `Info.plist` 加：

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

这个键**只**允许 `.local` / IP 直连，不会降低对外 HTTPS 的安全要求。

Xcode 26+ 项目默认用 Generated Info.plist，可以在 target → Build Settings → `INFOPLIST_KEY_*` 里加：`INFOPLIST_KEY_NSAppTransportSecurity = ...`；也可以直接在 target → Info 面板里加键。选择其一即可，确保 `Info.plist` 或生成的 Info 里有此配置。

- [ ] **Step 3：编译 + 运行一次 App 确认 baseURL 读取**

临时在 `ContentView.swift` 里加一行 `print(Endpoints.baseURL)`，跑模拟器看控制台。

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 4：还原 ContentView 的临时 print + 提交**

```bash
git add ios-app/EchoIM/Core/Networking/Endpoints.swift ios-app/EchoIM/
git commit -m "feat(ios): add Endpoints with Info.plist override and local HTTP allowlist"
```

---

## Task 5：APIClient

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/APIClient.swift`
- Test: `ios-app/EchoIMTests/APIClientTests.swift`

`APIClient` 负责：拼 URL、注入 `Authorization: Bearer <token>`（可选）、编码 JSON body、解析响应 + 错误状态、用 `JSONDecoder` 做 snake_case + ISO 8601 fractional seconds 解码。

- [ ] **Step 1：写 JSON 解码测试（Message 的 created_at 用 ISO fractional seconds）**

`ios-app/EchoIMTests/APIClientTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("APIClient JSON decoding")
struct APIClientTests {
    @Test func decodesMessageWithFractionalSeconds() throws {
        let json = """
        {
          "id": 42,
          "conversation_id": 7,
          "sender_id": 3,
          "body": "hi",
          "message_type": "text",
          "media_url": null,
          "created_at": "2026-04-19T08:30:12.345Z",
          "client_temp_id": null
        }
        """.data(using: .utf8)!

        let decoder = APIClient.jsonDecoder
        let m = try decoder.decode(Message.self, from: json)
        #expect(m.id == 42)
        #expect(m.conversationId == 7)
        #expect(m.senderId == 3)
        #expect(m.body == "hi")
        #expect(m.messageType == "text")
        #expect(m.mediaUrl == nil)
        // 确认时间解析到毫秒精度
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(m.createdAt == iso.date(from: "2026-04-19T08:30:12.345Z"))
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`Message` / `APIClient.jsonDecoder` 未定义。

- [ ] **Step 3：实现 `Message`（最小字段集，后续阶段逐步扩充）**

暂时放在 `ios-app/EchoIM/Core/Networking/APIClient.swift` 顶部（P3 再拆出去）：

```swift
import Foundation

struct Message: Codable, Identifiable, Equatable {
    let id: Int
    let conversationId: Int
    let senderId: Int
    let body: String?
    let messageType: String
    let mediaUrl: String?
    let createdAt: Date
    let clientTempId: String?
}
```

- [ ] **Step 4：实现 APIClient**

接续同一文件：

```swift
struct AuthenticatedUser: Codable, Equatable {
    let id: Int
    let username: String
    let email: String
    let displayName: String?
    let avatarUrl: String?
}

struct AuthResponse: Codable, Equatable {
    let token: String
    let user: AuthenticatedUser
}

@MainActor
final class APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = iso.date(from: s) ?? isoNoFrac.date(from: s) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "invalid ISO 8601: \(s)")
        }
        return d
    }()

    /// 服务端请求体命名风格不统一：`auth/register` 用 camelCase（`inviteCode`），
    /// `messages POST` 用 snake_case（`recipient_id`、`client_temp_id`）。如果全局开
    /// `.convertToSnakeCase`，register 会发 `invite_code` 被 Fastify `additionalProperties: false`
    /// 拒掉；反过来全局不转又会漏 snake_case 字段。策略：
    ///   - Encoder 走 `.useDefaultKeys`（Swift 默认，camelCase 原样输出）
    ///   - 需要 snake_case 的请求体（messages / read 游标等）在 Encodable struct 里显式声明 CodingKeys
    /// 解码方向统一 `.convertFromSnakeCase`（因为响应都是 pg 列名 snake_case）。
    static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// 发起请求；body 为 Encodable 时自动 JSON 编码。
    func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        token: String? = nil,
        body: Encodable? = nil
    ) async throws -> Response {
        var req = URLRequest(url: Endpoints.url(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.jsonEncoder.encode(AnyEncodable(body))
        }

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch let urlErr as URLError {
            throw APIError.network(urlErr)
        }

        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.fromStatus(http.statusCode, body: data)
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try Self.jsonDecoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

struct EmptyResponse: Decodable {}

/// Encodable 存在类型时需要包一下（Swift 目前不能把 `Encodable` 直接编码）。
private struct AnyEncodable: Encodable {
    let base: Encodable
    init(_ base: Encodable) { self.base = base }
    func encode(to encoder: Encoder) throws { try base.encode(to: encoder) }
}
```

- [ ] **Step 5：运行测试**

```bash
$TEST
```

预期：`decodesMessageWithFractionalSeconds` 通过。

- [ ] **Step 6：加一个 HTTP 错误映射测试**

追加到 `APIClientTests.swift`：

```swift
@Test func throwsUnauthorizedOn401() async throws {
    let url = URL(string: "http://test.local/fail")!
    let (config, _) = MockURLProtocol.configure { _ in
        (HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
    }
    let client = await APIClient(session: URLSession(configuration: config))

    do {
        let _: EmptyResponse = try await client.request("x")
        Issue.record("expected .unauthorized")
    } catch let e as APIError {
        #expect(e == .unauthorized)
    }
}
```

加 `MockURLProtocol` 辅助（`ios-app/EchoIMTests/MockURLProtocol.swift`）：

```swift
import Foundation

/// URLProtocol 拦截器，每次 `configure` 都会分配独立 session ID，通过
/// `URLSessionConfiguration.httpAdditionalHeaders` 把 ID 注入到所有请求上，
/// `startLoading` 再按 ID 路由到对应 handler。
/// 这样即使 Swift Testing 并行跑 `APIClientTests` / `AuthRepositoryHTTPTests` 等
/// 多个 suite，它们各自的 handler 互不串台——全局静态 `handler` 变量会在并行执行
/// 下发生竞态，尤其是 CI 上 core 多时更容易偶发红。
final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    /// 测试里 handler 闭包常会捕获 `var captured: URLRequest?` 这样的可变局部变量，
    /// 写成 `@Sendable` 会编译失败。这里用 `nonisolated(unsafe)` 豁免 Swift 6 并发
    /// 检查，运行期靠 `lock` 串行化读写——测试闭包虽然非 Sendable，但每个 session ID
    /// 指向的 handler 只被对应 session 的单个请求调用，跨线程访问仅限字典本身的读写。
    nonisolated(unsafe) private static var handlers:
        [String: (URLRequest) -> (HTTPURLResponse, Data)] = [:]

    private static let sessionHeader = "X-Mock-Session-ID"

    /// 返回一个注入了独立 session ID 的 `URLSessionConfiguration`。
    /// 第二个返回值保留 `Void` 以维持既有调用方签名。
    static func configure(
        _ handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> (URLSessionConfiguration, Void) {
        let sid = UUID().uuidString
        lock.lock()
        handlers[sid] = handler
        lock.unlock()

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        cfg.httpAdditionalHeaders = [sessionHeader: sid]
        return (cfg, ())
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // 只拦带 session header 的请求；没带头就放行（防御性）。
        request.value(forHTTPHeaderField: sessionHeader) != nil
    }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }

    override func startLoading() {
        guard let sid = request.value(forHTTPHeaderField: Self.sessionHeader) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        Self.lock.lock()
        let h = Self.handlers[sid]
        Self.lock.unlock()
        guard let h else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let (resp, data) = h(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

**注意：** `request` 里 `path` 被 `Endpoints.url` 拼到 `Endpoints.baseURL` 上；上面测试用的是 mocked URLSession 不关心 baseURL，任何 path 都会被 MockURLProtocol 拦截。Session ID 由 `httpAdditionalHeaders` 注入到**每个**任务的 request 上，`canInit` 只拦带 header 的请求，因此不会误伤真实 URLSession。

- [ ] **Step 7：运行全部测试**

```bash
$TEST
```

预期：3 个测试全绿。

- [ ] **Step 8：提交**

```bash
git add ios-app/EchoIM/Core/Networking/APIClient.swift \
        ios-app/EchoIMTests/APIClientTests.swift \
        ios-app/EchoIMTests/MockURLProtocol.swift
git commit -m "feat(ios): add APIClient with JWT injection and snake_case JSON decoding"
```

---

## Task 6：KeychainTokenStore

**Files:**
- Create: `ios-app/EchoIM/Core/Storage/KeychainTokenStore.swift`
- Test: `ios-app/EchoIMTests/KeychainTokenStoreTests.swift`

- [ ] **Step 1：写测试**

`ios-app/EchoIMTests/KeychainTokenStoreTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("KeychainTokenStore", .serialized)
struct KeychainTokenStoreTests {
    @Test func saveLoadDelete() throws {
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try store.clear()
        #expect(try store.load() == nil)

        try store.save(token: "tok-1", userId: 42)
        let loaded = try store.load()
        #expect(loaded?.token == "tok-1")
        #expect(loaded?.userId == 42)

        try store.clear()
        #expect(try store.load() == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`KeychainTokenStore` 未定义。

- [ ] **Step 3：实现**

`ios-app/EchoIM/Core/Storage/KeychainTokenStore.swift`：

```swift
import Foundation
import KeychainAccess

struct StoredToken: Equatable {
    let token: String
    let userId: Int
}

final class KeychainTokenStore {
    private let keychain: Keychain
    private let tokenKey = "jwt"
    private let userIdKey = "userId"

    init(service: String = "com.echoim.app") {
        self.keychain = Keychain(service: service)
    }

    func save(token: String, userId: Int) throws {
        try keychain.set(token, key: tokenKey)
        try keychain.set(String(userId), key: userIdKey)
    }

    func load() throws -> StoredToken? {
        guard let token = try keychain.get(tokenKey),
              let uidStr = try keychain.get(userIdKey),
              let uid = Int(uidStr) else { return nil }
        return StoredToken(token: token, userId: uid)
    }

    func clear() throws {
        try keychain.remove(tokenKey)
        try keychain.remove(userIdKey)
    }
}
```

- [ ] **Step 4：运行测试**

```bash
$TEST
```

预期：绿。注意 Keychain 在模拟器上需要目标签名；如果首次跑失败，确认 `EchoIMTests` 的 Signing & Capabilities → Team = `EchoIM` 一致。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Core/Storage/KeychainTokenStore.swift \
        ios-app/EchoIMTests/KeychainTokenStoreTests.swift
git commit -m "feat(ios): add KeychainTokenStore"
```

---

## Task 7：AuthRepository（protocol + impl + 错误映射）

**Files:**
- Create: `ios-app/EchoIM/Features/Auth/AuthRepository.swift`
- Test: `ios-app/EchoIMTests/AuthRepositoryTests.swift`

错误映射需求来自设计文档 §8 P1：

**注册：**
- 403 "Invalid invite code" → `.invalidInviteCode`（View 展现："邀请码无效" 字段红字 **+** toast，设计文档明示"字段 + toast"）
- 409 "Email already in use" → `.emailTaken`（字段红字）
- 409 "Username already taken" → `.usernameTaken`（字段红字）
- 400 + 服务端消息文本 → `.fieldValidation(field: <识别到的字段>, message: <原文案>)`。服务端 400 消息示例（见 `server/src/routes/auth.ts:37-41` 与 Fastify schema 校验）：
  - `Invalid email address` / `body/email ...` → `field: .email`
  - `Username must be at least 3 characters` / `body/username ...` → `field: .username`
  - `body/password ...` → `field: .password`
  - `body/inviteCode ...` → `field: .inviteCode`
  - 识别不出来 → `field: nil`，落 toast

**登录：**
- 401 → `.invalidCredentials`（View 展现：**toast** "邮箱或密码错误"，不是页内红字——设计文档 §8 P1 "错误密码 toast"）
- 其它 → `.unknown(underlying)` + toast

- [ ] **Step 1：写错误映射的失败测试（先不碰网络，只测 mapError）**

`ios-app/EchoIMTests/AuthRepositoryTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@Suite("AuthRepository error mapping")
struct AuthRepositoryErrorMapTests {
    func makeBody(_ msg: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": msg])
    }

    @Test func invalidInviteCodeIs403() {
        let err = AuthRepositoryImpl.mapRegisterError(.http(status: 403, body: makeBody("Invalid invite code")))
        #expect(err == .invalidInviteCode)
    }

    @Test func emailTakenIs409() {
        let err = AuthRepositoryImpl.mapRegisterError(.http(status: 409, body: makeBody("Email already in use")))
        #expect(err == .emailTaken)
    }

    @Test func usernameTakenIs409() {
        let err = AuthRepositoryImpl.mapRegisterError(.http(status: 409, body: makeBody("Username already taken")))
        #expect(err == .usernameTaken)
    }

    @Test func fieldValidationEmailIs400() {
        let err = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody("Invalid email address")))
        if case .fieldValidation(let field, let msg) = err {
            #expect(field == .email)
            #expect(msg == "Invalid email address")
        } else {
            Issue.record("expected .fieldValidation(email), got \(err)")
        }
    }

    @Test func fieldValidationUsernameIs400() {
        let err = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody("Username must be at least 3 characters")))
        if case .fieldValidation(let field, _) = err {
            #expect(field == .username)
        } else {
            Issue.record("expected .fieldValidation(username), got \(err)")
        }
    }

    @Test func fieldValidationPasswordIs400() {
        let err = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody("body/password must NOT have fewer than 8 characters")))
        if case .fieldValidation(let field, _) = err {
            #expect(field == .password)
        } else {
            Issue.record("expected .fieldValidation(password)")
        }
    }

    @Test func fieldValidationInviteCodeIs400() {
        let err = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody("body/inviteCode must NOT have fewer than 1 character")))
        if case .fieldValidation(let field, _) = err {
            #expect(field == .inviteCode)
        } else {
            Issue.record("expected .fieldValidation(inviteCode)")
        }
    }

    @Test func fieldValidationUnknownFieldFallsToToast() {
        let err = AuthRepositoryImpl.mapRegisterError(
            .http(status: 400, body: makeBody("something obscure")))
        if case .fieldValidation(let field, _) = err {
            #expect(field == nil)
        } else {
            Issue.record("expected .fieldValidation(nil)")
        }
    }

    @Test func loginInvalidCredentialsIs401() {
        let err = AuthRepositoryImpl.mapLoginError(.unauthorized)
        #expect(err == .invalidCredentials)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`AuthRepositoryImpl` 未定义。

- [ ] **Step 3：实现 AuthRepository**

`ios-app/EchoIM/Features/Auth/AuthRepository.swift`：

```swift
import Foundation

enum RegisterField: String, Equatable, Sendable {
    case inviteCode, username, email, password
}

enum AuthError: Error, Equatable {
    case invalidCredentials
    case invalidInviteCode
    case emailTaken
    case usernameTaken
    /// field == nil 代表服务端返回了 400 但无法识别到具体字段，View 落 toast
    case fieldValidation(field: RegisterField?, message: String)
    case network
    case unknown(String)
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// camelCase 原样 encode（与服务端 `POST /api/auth/register` schema 对齐，见 server/src/routes/auth.ts:10-17）。
/// 依赖 APIClient.jsonEncoder 为 useDefaultKeys。
struct RegisterRequest: Encodable {
    let username: String
    let email: String
    let password: String
    let inviteCode: String
}

protocol AuthRepository {
    func login(email: String, password: String) async throws -> AuthResponse
    func register(_ req: RegisterRequest) async throws -> AuthResponse
    func logout() async
}

@MainActor
final class AuthRepositoryImpl: AuthRepository {
    private let api: APIClient
    private let tokenStore: KeychainTokenStore

    init(api: APIClient, tokenStore: KeychainTokenStore) {
        self.api = api
        self.tokenStore = tokenStore
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        do {
            let resp: AuthResponse = try await api.request(
                Endpoints.Auth.login,
                method: "POST",
                body: LoginRequest(email: email, password: password))
            try tokenStore.save(token: resp.token, userId: resp.user.id)
            return resp
        } catch let e as APIError {
            throw Self.mapLoginError(e)
        }
    }

    func register(_ req: RegisterRequest) async throws -> AuthResponse {
        do {
            let resp: AuthResponse = try await api.request(
                Endpoints.Auth.register,
                method: "POST",
                body: req)
            try tokenStore.save(token: resp.token, userId: resp.user.id)
            return resp
        } catch let e as APIError {
            throw Self.mapRegisterError(e)
        }
    }

    func logout() async {
        try? tokenStore.clear()
    }

    static func mapLoginError(_ e: APIError) -> AuthError {
        switch e {
        case .unauthorized: return .invalidCredentials
        case .network: return .network
        case .decoding(let s): return .unknown(s)
        case .invalidResponse: return .unknown("invalid response")
        case .http(let status, let body):
            let s = String(data: body, encoding: .utf8) ?? ""
            return .unknown("\(status): \(s)")
        }
    }

    static func mapRegisterError(_ e: APIError) -> AuthError {
        guard case .http(let status, let body) = e else {
            if case .network = e { return .network }
            return .unknown(String(describing: e))
        }
        let msg = Self.extractErrorMessage(body)
        let lower = msg.lowercased()
        switch status {
        case 403 where lower.contains("invite"):
            return .invalidInviteCode
        case 409 where lower.contains("email"):
            return .emailTaken
        case 409 where lower.contains("username"):
            return .usernameTaken
        case 400:
            return .fieldValidation(field: Self.detectField(lower), message: msg)
        default:
            return .unknown("\(status): \(msg)")
        }
    }

    /// 识别服务端 400 消息里提到的字段。规则：
    ///   - 关键词匹配优先级：`invitecode` / `invite` > `username` > `email` > `password`
    ///     （`invitecode` 排最前是因为它最具体，避免 "invite code" 里 "code" 误伤）
    ///   - 识别不出返回 nil，让 View 落 toast
    static func detectField(_ lowerMsg: String) -> RegisterField? {
        if lowerMsg.contains("invitecode") || lowerMsg.contains("invite code")
            || lowerMsg.contains("invite") {
            return .inviteCode
        }
        if lowerMsg.contains("username") { return .username }
        if lowerMsg.contains("email") { return .email }
        if lowerMsg.contains("password") { return .password }
        return nil
    }

    private static func extractErrorMessage(_ body: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let msg = obj["error"] as? String {
            return msg
        }
        return String(data: body, encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 4：运行测试**

```bash
$TEST
```

预期：9 个 mapError 测试全绿。

- [ ] **Step 5：手动跑一次真实 login（作为端到端冒烟，不入自动化）**

启动后端（`docker compose up` 或 `npm --prefix server run dev`），在 Xcode 里加一次性的 Playground / `@main` test harness 不划算——直接进下一个 task，等 LoginView 接好后在模拟器里点一次。

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/Features/Auth/AuthRepository.swift \
        ios-app/EchoIMTests/AuthRepositoryTests.swift
git commit -m "feat(ios): add AuthRepository with field-level error mapping"
```

---

## Task 7.5：AuthRepository happy-path 集成测试

**Files:**
- Create: `ios-app/EchoIMTests/AuthRepositoryHTTPTests.swift`

**动机：** 纯映射测试无法发现"endpoint 拼错 / JSON key 不对 / token 忘存"这类 bug。这里用 `MockURLProtocol` 拦截 URLSession，验证真实请求的 URL path、method、body JSON key 以及成功后 `tokenStore.save` 被调用。特别关注：`register` 请求体**必须**含 `inviteCode`（camelCase），不能出现 `invite_code`（否则服务端 `additionalProperties: false` 直接 400）——这是前面 `APIClient.jsonEncoder` 不开 `.convertToSnakeCase` 的直接验证点。

- [ ] **Step 1：写测试**

`ios-app/EchoIMTests/AuthRepositoryHTTPTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("AuthRepository HTTP integration (mocked URLSession)")
struct AuthRepositoryHTTPTests {

    private func makeClient(handler: @escaping (URLRequest) -> (HTTPURLResponse, Data))
    -> (APIClient, KeychainTokenStore) {
        let (config, _) = MockURLProtocol.configure(handler)
        let api = APIClient(session: URLSession(configuration: config))
        let tokenStore = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try? tokenStore.clear()
        return (api, tokenStore)
    }

    @Test func loginHitsCorrectEndpointAndStoresToken() async throws {
        var captured: URLRequest?
        let (api, tokenStore) = makeClient { req in
            captured = req
            let body = """
            {"token":"jwt-abc","user":{"id":7,"username":"alice","email":"a@b.c","display_name":null,"avatar_url":null}}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        let resp = try await repo.login(email: "a@b.c", password: "password123")

        #expect(captured?.httpMethod == "POST")
        #expect(captured?.url?.path.hasSuffix("/api/auth/login") == true)

        let bodyData = try #require(captured?.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(json?["email"] as? String == "a@b.c")
        #expect(json?["password"] as? String == "password123")
        #expect(json?.count == 2)   // 无多余字段

        let stored = try tokenStore.load()
        #expect(stored?.token == "jwt-abc")
        #expect(stored?.userId == 7)
        #expect(resp.user.username == "alice")

        try tokenStore.clear()
    }

    @Test func registerSendsCamelCaseInviteCodeAndStoresToken() async throws {
        var captured: URLRequest?
        let (api, tokenStore) = makeClient { req in
            captured = req
            let body = """
            {"token":"jwt-xyz","user":{"id":11,"username":"bob","email":"b@c.d","display_name":"Bob","avatar_url":null}}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        _ = try await repo.register(RegisterRequest(
            username: "bob", email: "b@c.d",
            password: "password123", inviteCode: "INVITE1"))

        #expect(captured?.url?.path.hasSuffix("/api/auth/register") == true)
        let bodyData = try #require(captured?.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        // 关键断言：必须是 inviteCode（camelCase），不能是 invite_code
        #expect(json?["inviteCode"] as? String == "INVITE1")
        #expect(json?["invite_code"] == nil)
        #expect(json?["username"] as? String == "bob")
        #expect(json?["email"] as? String == "b@c.d")
        #expect(json?["password"] as? String == "password123")

        let stored = try tokenStore.load()
        #expect(stored?.token == "jwt-xyz")
        #expect(stored?.userId == 11)

        try tokenStore.clear()
    }

    @Test func registerReturns403InvalidInviteCode() async throws {
        let (api, tokenStore) = makeClient { req in
            let body = try! JSONSerialization.data(withJSONObject: ["error": "Invalid invite code"])
            return (HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        do {
            _ = try await repo.register(RegisterRequest(
                username: "x", email: "x@y.z", password: "12345678", inviteCode: "BAD"))
            Issue.record("expected throw")
        } catch let e as AuthError {
            #expect(e == .invalidInviteCode)
        }
        // 失败时不应写 token
        #expect(try tokenStore.load() == nil)
    }

    @Test func loginReturns401InvalidCredentials() async throws {
        let (api, tokenStore) = makeClient { req in
            let body = try! JSONSerialization.data(withJSONObject: ["error": "Invalid email or password"])
            return (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, body)
        }
        let repo = AuthRepositoryImpl(api: api, tokenStore: tokenStore)

        do {
            _ = try await repo.login(email: "a@b.c", password: "wrong")
            Issue.record("expected throw")
        } catch let e as AuthError {
            #expect(e == .invalidCredentials)
        }
        #expect(try tokenStore.load() == nil)
    }
}
```

- [ ] **Step 2：运行测试**

```bash
$TEST
```

预期：4 个 HTTP 测试全绿。如果 `registerSendsCamelCaseInviteCodeAndStoresToken` 挂在 `invite_code` 非 nil，说明 `APIClient.jsonEncoder` 的 `.convertToSnakeCase` 没去掉——回 Task 5 修正。

- [ ] **Step 3：提交**

```bash
git add ios-app/EchoIMTests/AuthRepositoryHTTPTests.swift
git commit -m "test(ios): add AuthRepository HTTP happy-path and error path tests"
```

---

## Task 8：AppContainer（最小版本）

**Files:**
- Create: `ios-app/EchoIM/App/AppContainer.swift`

本阶段不引入 `UserSession`（P3/P4 随 WS/SwiftData 一起引入），`AppContainer` 只持 `tokenStore`、`apiClient`、`currentUser`。

- [ ] **Step 1：写测试**

`ios-app/EchoIMTests/AppContainerTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("AppContainer", .serialized)
struct AppContainerTests {
    private func makeContainer(resetArg: Bool = false)
    -> (AppContainer, KeychainTokenStore) {
        let store = KeychainTokenStore(service: "com.echoim.test.\(UUID().uuidString)")
        try? store.clear()
        let container = AppContainer(
            tokenStore: store,
            apiClient: APIClient(),
            resetKeychainOnLaunch: resetArg)
        return (container, store)
    }

    @Test func bootstrapRestoresCurrentUserFromKeychain() throws {
        let (container, store) = makeContainer()
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.currentUser?.id == 42)
        try store.clear()
    }

    @Test func bootstrapLeavesCurrentUserNilWhenNoToken() {
        let (container, _) = makeContainer()
        container.bootstrap()
        #expect(container.currentUser == nil)
    }

    @Test func logoutClearsKeychainAndCurrentUser() async throws {
        let (container, store) = makeContainer()
        try store.save(token: "t", userId: 42)
        container.bootstrap()
        #expect(container.currentUser?.id == 42)

        await container.logout()

        #expect(container.currentUser == nil)
        #expect(try store.load() == nil)
    }

    @Test func resetKeychainFlagWipesOnBootstrap() throws {
        let (container, store) = makeContainer(resetArg: true)
        try store.save(token: "t", userId: 42)

        container.bootstrap()

        #expect(container.currentUser == nil)
        #expect(try store.load() == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

预期：`AppContainer` 未定义、`resetKeychainOnLaunch` 参数未知。

- [ ] **Step 3：实现 AppContainer**

`ios-app/EchoIM/App/AppContainer.swift`：

```swift
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppContainer {
    let tokenStore: KeychainTokenStore
    let apiClient: APIClient
    var currentUser: AuthenticatedUser?     // P1 阶段用这个判断登录态；P3 引入 UserSession 后挪走

    /// 仅 UI 测试传 true（来自 `-uitest-reset-keychain` 启动参数），
    /// 让每次 UI 测试启动都从未登录态开始。
    private let resetKeychainOnLaunch: Bool

    init(tokenStore: KeychainTokenStore = KeychainTokenStore(),
         apiClient: APIClient = APIClient(),
         resetKeychainOnLaunch: Bool = false) {
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.resetKeychainOnLaunch = resetKeychainOnLaunch
    }

    func makeAuthRepository() -> AuthRepository {
        AuthRepositoryImpl(api: apiClient, tokenStore: tokenStore)
    }

    /// 冷启动时尝试从 Keychain 恢复登录态。
    /// P1 阶段：只要 token 存在就视为已登录（不拉 /api/users/me 验证——留给 P2）。
    /// 恢复时 currentUser.username 置为占位 "(restoring)"，P2 会在 bootstrap 尾部加一次
    /// /api/users/me 拉取；如 401 再调 logout() 回到登录页。
    func bootstrap() {
        if resetKeychainOnLaunch {
            try? tokenStore.clear()
            return
        }
        guard let stored = try? tokenStore.load() else { return }
        currentUser = AuthenticatedUser(
            id: stored.userId,
            username: "(restoring)",
            email: "",
            displayName: nil,
            avatarUrl: nil)
    }

    func handleLoginSuccess(_ resp: AuthResponse) {
        currentUser = resp.user
    }

    func logout() async {
        await makeAuthRepository().logout()
        currentUser = nil
    }
}
```

- [ ] **Step 4：运行测试**

```bash
$TEST
```

预期：4 个 AppContainer 测试全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/App/AppContainer.swift \
        ios-app/EchoIMTests/AppContainerTests.swift
git commit -m "feat(ios): add AppContainer with bootstrap and logout"
```

---

## Task 9：LoginViewModel

**Files:**
- Create: `ios-app/EchoIM/Features/Auth/LoginViewModel.swift`
- Test: `ios-app/EchoIMTests/LoginViewModelTests.swift`

状态机：`.idle` → `.submitting` → `.success` / `.failed(AuthError)`。VM 不持 Container，只持 repo + 成功回调。

- [ ] **Step 1：写失败测试（stub AuthRepository）**

`ios-app/EchoIMTests/LoginViewModelTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("LoginViewModel")
struct LoginViewModelTests {
    final class StubRepo: AuthRepository {
        var loginResult: Result<AuthResponse, Error> = .failure(AuthError.unknown(""))
        func login(email: String, password: String) async throws -> AuthResponse {
            try loginResult.get()
        }
        func register(_ req: RegisterRequest) async throws -> AuthResponse { fatalError() }
        func logout() async {}
    }

    @Test func submitsAndReportsSuccess() async {
        let repo = StubRepo()
        let user = AuthenticatedUser(id: 1, username: "u", email: "a@b.c", displayName: nil, avatarUrl: nil)
        repo.loginResult = .success(AuthResponse(token: "t", user: user))

        var received: AuthResponse?
        let vm = LoginViewModel(repo: repo) { received = $0 }
        vm.email = "a@b.c"
        vm.password = "12345678"
        await vm.submit()

        #expect(received?.user == user)
        #expect(vm.state == .success)
        #expect(vm.toast == nil)
    }

    @Test func invalidCredentialsSurfacesAsToast() async {
        let repo = StubRepo()
        repo.loginResult = .failure(AuthError.invalidCredentials)
        let vm = LoginViewModel(repo: repo) { _ in }
        vm.email = "a@b.c"
        vm.password = "wrong"
        await vm.submit()

        // 设计文档 §8 P1 明确："错误密码 toast"
        #expect(vm.toast == "邮箱或密码错误")
        if case .failed(let err) = vm.state {
            #expect(err == .invalidCredentials)
        } else {
            Issue.record("expected .failed(.invalidCredentials), got \(vm.state)")
        }
    }

    @Test func networkErrorSurfacesAsToast() async {
        let repo = StubRepo()
        repo.loginResult = .failure(AuthError.network)
        let vm = LoginViewModel(repo: repo) { _ in }
        vm.email = "a@b.c"
        vm.password = "12345678"
        await vm.submit()
        #expect(vm.toast == "网络错误，请检查连接")
    }

    @Test func blocksEmptyInput() async {
        let repo = StubRepo()
        let vm = LoginViewModel(repo: repo) { _ in }
        vm.email = ""
        vm.password = ""
        await vm.submit()
        #expect(vm.toast == "邮箱和密码不能为空")
        if case .failed(let err) = vm.state, case .fieldValidation = err { /* ok */ }
        else { Issue.record("expected .fieldValidation, got \(vm.state)") }
    }

    @Test func submittingClearsStaleToast() async {
        let repo = StubRepo()
        let user = AuthenticatedUser(id: 1, username: "u", email: "a@b.c", displayName: nil, avatarUrl: nil)
        let vm = LoginViewModel(repo: repo) { _ in }
        vm.toast = "旧错误"
        repo.loginResult = .success(AuthResponse(token: "t", user: user))
        vm.email = "a@b.c"
        vm.password = "12345678"
        await vm.submit()
        #expect(vm.toast == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

- [ ] **Step 3：实现 LoginViewModel**

`ios-app/EchoIM/Features/Auth/LoginViewModel.swift`：

```swift
import Foundation

@MainActor
@Observable
final class LoginViewModel {
    enum State: Equatable {
        case idle
        case submitting
        case failed(AuthError)
        case success
    }

    var email = ""
    var password = ""
    var state: State = .idle
    /// 登录错误统一走 toast（设计文档 §8 P1："错误密码 toast"）。
    /// 空值校验的 "邮箱和密码不能为空" 也走 toast 保持一致。
    var toast: String?

    private let repo: AuthRepository
    private let onSuccess: (AuthResponse) -> Void

    init(repo: AuthRepository, onSuccess: @escaping (AuthResponse) -> Void) {
        self.repo = repo
        self.onSuccess = onSuccess
    }

    func submit() async {
        toast = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            let msg = "邮箱和密码不能为空"
            toast = msg
            state = .failed(.fieldValidation(field: nil, message: msg))
            return
        }
        state = .submitting
        do {
            let resp = try await repo.login(email: trimmedEmail, password: password)
            state = .success
            onSuccess(resp)
        } catch let e as AuthError {
            state = .failed(e)
            toast = Self.toastMessage(for: e)
        } catch {
            state = .failed(.unknown(String(describing: error)))
            toast = "登录失败，请重试"
        }
    }

    static func toastMessage(for e: AuthError) -> String {
        switch e {
        case .invalidCredentials: return "邮箱或密码错误"
        case .network: return "网络错误，请检查连接"
        case .fieldValidation(_, let m): return m
        default: return "登录失败，请重试"
        }
    }
}
```

- [ ] **Step 4：运行测试**

```bash
$TEST
```

预期：5 个 LoginViewModel 测试全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Auth/LoginViewModel.swift \
        ios-app/EchoIMTests/LoginViewModelTests.swift
git commit -m "feat(ios): add LoginViewModel with toast-based error surfacing"
```

---

## Task 10：RegisterViewModel

**Files:**
- Create: `ios-app/EchoIM/Features/Auth/RegisterViewModel.swift`
- Test: `ios-app/EchoIMTests/RegisterViewModelTests.swift`

**客户端校验**（对齐 Web）：`inviteCode` 非空、`username` ≥ 3、`email` 满足简单正则、`password` ≥ 8。

- [ ] **Step 1：写校验 & 错误分派测试**

`ios-app/EchoIMTests/RegisterViewModelTests.swift`：

```swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("RegisterViewModel")
struct RegisterViewModelTests {
    final class StubRepo: AuthRepository {
        var registerResult: Result<AuthResponse, Error> = .failure(AuthError.unknown(""))
        func login(email: String, password: String) async throws -> AuthResponse { fatalError() }
        func register(_ req: RegisterRequest) async throws -> AuthResponse { try registerResult.get() }
        func logout() async {}
    }

    func vm(_ repo: AuthRepository) -> RegisterViewModel {
        RegisterViewModel(repo: repo) { _ in }
    }

    @Test func localValidationBlocksShortUsername() async {
        let v = vm(StubRepo())
        v.username = "ab"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = "X"
        await v.submit()
        #expect(v.usernameError != nil)
        if case .failed = v.state { /* ok */ } else { Issue.record("expected .failed") }
    }

    @Test func localValidationBlocksBadEmail() async {
        let v = vm(StubRepo())
        v.username = "alice"; v.email = "not-email"; v.password = "12345678"; v.inviteCode = "X"
        await v.submit()
        #expect(v.emailError != nil)
    }

    @Test func localValidationBlocksShortPassword() async {
        let v = vm(StubRepo())
        v.username = "alice"; v.email = "a@b.co"; v.password = "short"; v.inviteCode = "X"
        await v.submit()
        #expect(v.passwordError != nil)
    }

    @Test func localValidationBlocksEmptyInvite() async {
        let v = vm(StubRepo())
        v.username = "alice"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = ""
        await v.submit()
        #expect(v.inviteCodeError != nil)
    }

    @Test func mapsEmailTakenToEmailErrorOnly() async {
        let repo = StubRepo(); repo.registerResult = .failure(AuthError.emailTaken)
        let v = vm(repo)
        v.username = "alice"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = "X"
        await v.submit()
        #expect(v.emailError == "邮箱已被注册")
        #expect(v.usernameError == nil)
        #expect(v.toast == nil)                 // 已有字段标红，不再额外 toast
    }

    @Test func mapsUsernameTakenToUsernameError() async {
        let repo = StubRepo(); repo.registerResult = .failure(AuthError.usernameTaken)
        let v = vm(repo)
        v.username = "alice"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = "X"
        await v.submit()
        #expect(v.usernameError == "用户名已被占用")
        #expect(v.emailError == nil)
    }

    @Test func mapsInvalidInviteCodeToFieldAndToast() async {
        let repo = StubRepo(); repo.registerResult = .failure(AuthError.invalidInviteCode)
        let v = vm(repo)
        v.username = "alice"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = "WRONG"
        await v.submit()
        // 设计文档 §8 P1："403 Invalid invite code → 标红 inviteCode 字段 + toast"
        #expect(v.inviteCodeError == "邀请码无效")
        #expect(v.toast == "邀请码无效")
    }

    @Test func mapsFieldValidationEmailToEmailError() async {
        let repo = StubRepo()
        repo.registerResult = .failure(
            AuthError.fieldValidation(field: .email, message: "Invalid email address"))
        let v = vm(repo)
        v.username = "alice"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = "X"
        await v.submit()
        #expect(v.emailError == "Invalid email address")
        #expect(v.toast == nil)
    }

    @Test func mapsFieldValidationUnknownToToast() async {
        let repo = StubRepo()
        repo.registerResult = .failure(
            AuthError.fieldValidation(field: nil, message: "server said something weird"))
        let v = vm(repo)
        v.username = "alice"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = "X"
        await v.submit()
        #expect(v.toast == "server said something weird")
        #expect(v.emailError == nil)
    }

    @Test func submitClearsStaleErrors() async {
        let repo = StubRepo()
        let user = AuthenticatedUser(id: 1, username: "alice", email: "a@b.co", displayName: nil, avatarUrl: nil)
        repo.registerResult = .success(AuthResponse(token: "t", user: user))
        let v = vm(repo)
        v.emailError = "stale"; v.usernameError = "stale"; v.toast = "stale"
        v.username = "alice"; v.email = "a@b.co"; v.password = "12345678"; v.inviteCode = "X"
        await v.submit()
        #expect(v.emailError == nil)
        #expect(v.usernameError == nil)
        #expect(v.toast == nil)
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
$TEST
```

- [ ] **Step 3：实现**

`ios-app/EchoIM/Features/Auth/RegisterViewModel.swift`：

```swift
import Foundation

@MainActor
@Observable
final class RegisterViewModel {
    enum State: Equatable {
        case idle
        case submitting
        case failed(AuthError)
        case success
    }

    var inviteCode = ""
    var username = ""
    var email = ""
    var password = ""

    var inviteCodeError: String?
    var usernameError: String?
    var emailError: String?
    var passwordError: String?
    var toast: String?
    var state: State = .idle

    private let repo: AuthRepository
    private let onSuccess: (AuthResponse) -> Void

    init(repo: AuthRepository, onSuccess: @escaping (AuthResponse) -> Void) {
        self.repo = repo
        self.onSuccess = onSuccess
    }

    func submit() async {
        clearFieldErrors()

        let trimmedUser = username.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedInvite = inviteCode.trimmingCharacters(in: .whitespaces)

        if trimmedInvite.isEmpty { inviteCodeError = "邀请码不能为空" }
        if trimmedUser.count < 3 { usernameError = "用户名至少 3 位" }
        if !Self.isValidEmail(trimmedEmail) { emailError = "邮箱格式不正确" }
        if password.count < 8 { passwordError = "密码至少 8 位" }

        guard inviteCodeError == nil, usernameError == nil,
              emailError == nil, passwordError == nil else {
            state = .failed(.fieldValidation(field: nil, message: "客户端校验未通过"))
            return
        }

        state = .submitting
        do {
            let resp = try await repo.register(RegisterRequest(
                username: trimmedUser, email: trimmedEmail,
                password: password, inviteCode: trimmedInvite))
            state = .success
            onSuccess(resp)
        } catch let e as AuthError {
            mapServerError(e)
            state = .failed(e)
        } catch {
            toast = "注册失败，请重试"
            state = .failed(.unknown(String(describing: error)))
        }
    }

    private func clearFieldErrors() {
        inviteCodeError = nil; usernameError = nil
        emailError = nil; passwordError = nil; toast = nil
    }

    private func mapServerError(_ e: AuthError) {
        switch e {
        case .invalidInviteCode:
            // 设计文档 §8 P1："字段 + toast" 双重呈现
            inviteCodeError = "邀请码无效"
            toast = "邀请码无效"
        case .emailTaken:
            emailError = "邮箱已被注册"
        case .usernameTaken:
            usernameError = "用户名已被占用"
        case .fieldValidation(let field, let msg):
            switch field {
            case .inviteCode: inviteCodeError = msg
            case .username: usernameError = msg
            case .email: emailError = msg
            case .password: passwordError = msg
            case .none: toast = msg
            }
        case .network:
            toast = "网络错误，请检查连接"
        default:
            toast = "注册失败，请重试"
        }
    }

    private static let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#

    static func isValidEmail(_ s: String) -> Bool {
        s.range(of: emailRegex, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 4：运行测试**

```bash
$TEST
```

预期：10 个 RegisterViewModel 测试全绿。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/Auth/RegisterViewModel.swift \
        ios-app/EchoIMTests/RegisterViewModelTests.swift
git commit -m "feat(ios): add RegisterViewModel with structured field errors"
```

---

## Task 11：LoginView + RegisterView + HomePlaceholderView

**Files:**
- Create: `ios-app/EchoIM/Features/Auth/LoginView.swift`
- Create: `ios-app/EchoIM/Features/Auth/RegisterView.swift`
- Create: `ios-app/EchoIM/Features/Home/HomePlaceholderView.swift`

View 不单测，靠编译 + 模拟器跑清单。

- [ ] **Step 1：LoginView**

`ios-app/EchoIM/Features/Auth/LoginView.swift`：

```swift
import SwiftUI

struct LoginView: View {
    @Bindable var vm: LoginViewModel
    var onNavigateToRegister: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("邮箱") {
                    TextField("you@example.com", text: $vm.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("loginEmail")
                }
                Section("密码") {
                    SecureField("至少 8 位", text: $vm.password)
                        .textContentType(.password)
                        .accessibilityIdentifier("loginPassword")
                }
                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        if case .submitting = vm.state {
                            ProgressView()
                        } else {
                            Text("登录").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.state == .submitting)
                    .accessibilityIdentifier("loginSubmit")
                }
                Section {
                    Button("没有账号？去注册", action: onNavigateToRegister)
                        .accessibilityIdentifier("loginGoRegister")
                }
            }
            .navigationTitle("登录")
            // 登录错误走 toast（设计文档 §8 P1："错误密码 toast"）
            .alert("登录失败",
                   isPresented: Binding(
                        get: { vm.toast != nil },
                        set: { if !$0 { vm.toast = nil } }
                   ),
                   presenting: vm.toast) { _ in
                Button("好", role: .cancel) { vm.toast = nil }
                    .accessibilityIdentifier("loginToastOK")
            } message: { msg in
                Text(msg)
            }
        }
    }
}
```

- [ ] **Step 2：RegisterView**

`ios-app/EchoIM/Features/Auth/RegisterView.swift`：

```swift
import SwiftUI

struct RegisterView: View {
    @Bindable var vm: RegisterViewModel
    var onBackToLogin: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                // 邀请码：服务端精确比较（server/src/routes/auth.ts:28-30），
                // 必须禁用自动首字母大写，否则用户输对也会被判无效。
                field("邀请码", text: $vm.inviteCode, error: vm.inviteCodeError, id: "regInvite")
                field("用户名", text: $vm.username, error: vm.usernameError, id: "regUsername")
                field("邮箱", text: $vm.email, error: vm.emailError, id: "regEmail",
                      keyboard: .emailAddress, contentType: .emailAddress)
                secureField("密码", text: $vm.password, error: vm.passwordError, id: "regPassword")

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        if case .submitting = vm.state {
                            ProgressView()
                        } else {
                            Text("注册").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.state == .submitting)
                    .accessibilityIdentifier("regSubmit")
                }
                Section {
                    Button("已有账号？返回登录", action: onBackToLogin)
                        .accessibilityIdentifier("regGoLogin")
                }
            }
            .navigationTitle("注册")
            .alert("注册失败",
                   isPresented: Binding(
                        get: { vm.toast != nil },
                        set: { if !$0 { vm.toast = nil } }
                   ),
                   presenting: vm.toast) { _ in
                Button("好", role: .cancel) { vm.toast = nil }
                    .accessibilityIdentifier("regToastOK")
            } message: { msg in
                Text(msg)
            }
        }
    }

    /// 注册表单字段默认 `autocap: .never`——用户名 / 邮箱 / 邀请码都是精确匹配，首字母大写没意义且会误伤。
    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, error: String?, id: String,
                       autocap: TextInputAutocapitalization = .never,
                       keyboard: UIKeyboardType = .default,
                       contentType: UITextContentType? = nil) -> some View {
        Section(title) {
            TextField(title, text: text)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .textContentType(contentType)
                .accessibilityIdentifier(id)
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
    }

    @ViewBuilder
    private func secureField(_ title: String, text: Binding<String>, error: String?, id: String)
    -> some View {
        Section(title) {
            SecureField(title, text: text)
                .textContentType(.newPassword)
                .accessibilityIdentifier(id)
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
    }
}
```

- [ ] **Step 3：HomePlaceholderView**

`ios-app/EchoIM/Features/Home/HomePlaceholderView.swift`：

```swift
import SwiftUI

struct HomePlaceholderView: View {
    let user: AuthenticatedUser
    var onLogout: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("已登录")
                    .font(.title2)
                Text(user.displayName ?? user.username)
                    .font(.headline)
                    .accessibilityIdentifier("homeUsername")
                Text(user.email).foregroundStyle(.secondary)
                Button("登出") {
                    Task { await onLogout() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("homeLogout")
            }
            .padding()
            .navigationTitle("EchoIM")
        }
    }
}
```

- [ ] **Step 4：编译**

```bash
$BUILD
```

预期：`BUILD SUCCEEDED`。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIM/Features/
git commit -m "feat(ios): add Login / Register / Home placeholder views"
```

---

## Task 12：RootView + EchoIMApp 集成

**Files:**
- Create: `ios-app/EchoIM/App/RootView.swift`
- Modify: `ios-app/EchoIM/EchoIMApp.swift`
- Delete: `ios-app/EchoIM/ContentView.swift`

- [ ] **Step 1：RootView**

`ios-app/EchoIM/App/RootView.swift`：

```swift
import SwiftUI

struct RootView: View {
    /// bootstrap 必须**在首帧渲染前**同步完成，否则 Keychain 里有 token 时仍会先闪一下
    /// LoginView 再切到 Home——放在 `.task { bootstrap() }` 里就会有这个闪烁。
    /// 所以在 @State 初始化闭包里直接跑 bootstrap()，container 进入 view tree 时
    /// currentUser 已经是终态。
    @State private var container: AppContainer = {
        let reset = CommandLine.arguments.contains("-uitest-reset-keychain")
        let c = AppContainer(resetKeychainOnLaunch: reset)
        c.bootstrap()
        return c
    }()
    @State private var showRegister = false

    var body: some View {
        Group {
            if let user = container.currentUser {
                HomePlaceholderView(user: user) {
                    await container.logout()
                    // 登出后无论之前从 Login 还是 Register 进的 Home，都回到 Login，
                    // 不要让残留的 showRegister=true 把用户带回注册页。
                    showRegister = false
                }
            } else if showRegister {
                RegisterView(vm: makeRegisterVM()) {
                    showRegister = false
                }
            } else {
                LoginView(vm: makeLoginVM()) {
                    showRegister = true
                }
            }
        }
        .animation(.default, value: container.currentUser?.id)
        .animation(.default, value: showRegister)
    }

    private func makeLoginVM() -> LoginViewModel {
        LoginViewModel(repo: container.makeAuthRepository()) { resp in
            container.handleLoginSuccess(resp)
        }
    }

    private func makeRegisterVM() -> RegisterViewModel {
        // 注册成功后复位 showRegister，否则从 Home 登出会落回 RegisterView
        // 而不是 LoginView（showRegister 还停在 true）。
        RegisterViewModel(repo: container.makeAuthRepository()) { resp in
            container.handleLoginSuccess(resp)
            showRegister = false
        }
    }
}
```

- [ ] **Step 2：改 EchoIMApp.swift**

`ios-app/EchoIM/EchoIMApp.swift`：

```swift
import SwiftUI

@main
struct EchoIMApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 3：删除 ContentView.swift**

```bash
rm ios-app/EchoIM/ContentView.swift
```

- [ ] **Step 4：编译**

```bash
$BUILD
```

- [ ] **Step 5：模拟器手工验证清单**

启动后端（本地 `:3000` 有 `/api/auth/login` / `/api/auth/register` 能访问）。用 Xcode Run（Cmd+R）起模拟器，依次验证：

- [ ] 冷启动（Keychain 无 token）直接显示 LoginView（title "登录"），**不闪其它界面**
- [ ] 冷启动（Keychain 有 token，如前一次 Login 成功过）直接显示 HomeView，**不闪 LoginView**（bootstrap 必须在首帧前同步完成）
- [ ] 点"没有账号？去注册"切到 RegisterView
- [ ] 点"已有账号？返回登录"切回 LoginView
- [ ] **从 Register 进入 Home 再登出**：必须回到 LoginView，不能停在 RegisterView（这验证 `showRegister = false` 的双复位点：注册成功 onSuccess + 登出后）
- [ ] 把邀请码字段输个 "abc"——键盘**不应**自动把 a 大写；对比用户名字段也同样（两者都走 `autocap: .never`）
- [ ] Register 四字段任一不填、或邮箱格式错、密码 < 8 位 → 提交按钮点下去在对应字段下显示红色错误，不发起网络请求（看后端日志确认）
- [ ] Register 用错误邀请码 → 邀请码字段红字 "邀请码无效" **且** 同时弹出 alert "邀请码无效"（设计文档 §8 P1："字段 + toast"）
- [ ] Register 用已注册邮箱 → 邮箱字段红字 "邮箱已被注册"，不弹 alert
- [ ] Register 新账号全流程 → 进入 HomePlaceholderView，显示用户名
- [ ] HomeView 点"登出" → 回到 LoginView
- [ ] 登出后杀 App 再启动 → 仍是 LoginView（Keychain 已清）
- [ ] Login 成功 → HomeView；杀 App 再启动 → 直接进 HomeView（Keychain 有 token，进 bootstrap 路径；用户名显示 "(restoring)"——P2 会接 `/api/users/me` 来填真名）
- [ ] Login 错误密码 → 弹出 alert "邮箱或密码错误"，点"好"关闭 alert（不是页内红字——设计文档 §8 P1 明确 toast）
- [ ] 断网后 Login → 弹出 alert "网络错误，请检查连接"

- [ ] **Step 6：提交**

```bash
git add ios-app/EchoIM/App/ ios-app/EchoIM/EchoIMApp.swift
git rm ios-app/EchoIM/ContentView.swift
git commit -m "feat(ios): wire RootView with login / register / home switching"
```

---

## Task 13：XCUITest smoke

**Files:**
- Create: `ios-app/EchoIMUITests/LoginSmokeTests.swift`

只覆盖 "输入 → 登录 → 看到 HomeView" 的 golden path。后端必须在跑。

- [ ] **Step 1：准备测试账号**

手动通过 RegisterView 或 `curl` 创建一个已知账号，比如 `smoke@test.local` / `password123`。记下来。

- [ ] **Step 2：写测试**

`ios-app/EchoIMUITests/LoginSmokeTests.swift`：

```swift
import XCTest

final class LoginSmokeTests: XCTestCase {
    func testLoginHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        password.tap()
        password.typeText("password123")

        app.buttons["loginSubmit"].tap()

        let username = app.staticTexts["homeUsername"]
        XCTAssertTrue(username.waitForExistence(timeout: 10))
    }
}
```

- [ ] **Step 3：确认 `-uitest-reset-keychain` 流水已通**

该启动参数已经在 Task 8 / Task 12 闭环：
- Task 8 `AppContainer.init(resetKeychainOnLaunch:)` 接受 flag，`bootstrap()` 在 flag=true 时 `tokenStore.clear()` 后直接 return
- Task 12 `RootView` 读 `CommandLine.arguments` 把 flag 传进去
- 本 Task 的 `launchArguments += ["-uitest-reset-keychain"]` 触发此路径

验证：

```bash
grep -n "uitest-reset-keychain" ios-app/EchoIM/App/AppContainer.swift ios-app/EchoIM/App/RootView.swift ios-app/EchoIMUITests/LoginSmokeTests.swift
```

预期：三个文件都出现引用。

- [ ] **Step 4：跑 UI 测试**

后端在跑，账号已建。

```bash
$UITEST
```

预期：`LoginSmokeTests.testLoginHappyPath` 绿。如果红，先看截图（`xcresult` bundle 里有）排查元素 identifier 是否对上。

- [ ] **Step 5：提交**

```bash
git add ios-app/EchoIMUITests/LoginSmokeTests.swift
git commit -m "test(ios): add login smoke UI test"
```

---

## Task 14：P1 收尾 + README 记录

**Files:**
- Create: `ios-app/README.md`（如不存在）

- [ ] **Step 1：写一份最小 README**

`ios-app/README.md`：

````markdown
# EchoIM iOS

## Prerequisites
- Xcode 26+
- iOS 17+ simulator / device
- Backend running at `http://localhost:3000` (see root `docker compose up`)

## Run
Open `EchoIM.xcodeproj`, choose iPhone 15 simulator, Cmd+R.

To point at a different backend, set `EchoIMBaseURL` in Info.plist (e.g. `http://192.168.1.10:3000`).

## Test
```
xcodebuild -project EchoIM.xcodeproj -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

UI smoke tests require backend running + a seeded account `smoke@test.local / password123`.

## Status
P1 done: scaffold + login/register/home.
P2-P8 tracked in `docs/superpowers/specs/2026-04-17-ios-app-design.md` §8.
````

- [ ] **Step 2：全量 build + test**

```bash
$BUILD
$TEST
$UITEST
```

三个都绿。

- [ ] **Step 3：最终提交**

```bash
git add ios-app/README.md
git commit -m "docs(ios): add README for P1 scaffold"
```

---

## Self-Review（完成前必过）

- [ ] **P1 覆盖设计 §8**：注册、登录、登出、Keychain 持久化、字段级错误（含 field + toast 双呈现）、Login ↔ Register 互跳、占位首页、错密码 toast、邀请码精确比较（`autocap: .never`）—— 每一项都指向具体 Task。
- [ ] **Placeholder 扫描**：`grep -rn -iE "tbd|todo|implement later|similar to task" docs/superpowers/plans/2026-04-19-ios-p1-scaffold-auth.md` 应为空。
- [ ] **命名一致**：`AuthRepository.login` / `register` / `logout`；`AuthError.fieldValidation(field:message:)` 形状在 AuthRepositoryImpl / LoginViewModel / RegisterViewModel / 测试里完全一致；`RegisterField` 枚举大小写（inviteCode、username、email、password）全文件一致；`AppContainer.makeAuthRepository()` 在 RootView 使用。无偏差。
- [ ] **编码策略契约**：`APIClient.jsonEncoder` 不开 `.convertToSnakeCase`；`RegisterRequest` 依赖默认 camelCase 输出；`AuthRepositoryHTTPTests.registerSendsCamelCaseInviteCodeAndStoresToken` 显式断言 `invite_code == nil`。
- [ ] **happy-path 被自动化覆盖**：Task 7.5 (AuthRepository HTTP) + Task 8 (AppContainer bootstrap/logout) + Task 13 (XCUITest login smoke) —— 至少 endpoint / body / token 存储 / Keychain 恢复这 4 个环节有断言。
- [ ] **RootView 状态流正确**：
  - bootstrap 在 `@State` init 闭包里同步跑，不在 `.task` 里——有 token 的冷启动首帧就是 HomeView，无闪烁
  - 注册成功 onSuccess 闭包复位 `showRegister = false`
  - 登出闭包也复位 `showRegister = false`，防止从 Register 进 Home 再登出时回到 RegisterView
- [ ] **MockURLProtocol 并行安全**：handler 按 session ID 字典路由，`httpAdditionalHeaders` 注入 `X-Mock-Session-ID`；字典访问全部 `NSLock` 保护。两个 HTTP 测试 suite 不需要 `.serialized` 也能安全并行跑。
- [ ] **工作目录一致**：所有路径都用 `ios-app/EchoIM/...` 绝对于 repo root。命令里 `$BUILD` / `$TEST` 引用 `ios-app/EchoIM.xcodeproj`。无裸相对路径。
- [ ] **测试 import**：所有用到 `Data` / `UUID` / `JSONSerialization` 的测试文件首部含 `import Foundation`（APIErrorTests、APIClientTests、KeychainTokenStoreTests、AuthRepositoryTests、AuthRepositoryHTTPTests、AppContainerTests、LoginViewModelTests、RegisterViewModelTests）。

---

## 未来阶段的依赖锚点（给 P2+ 计划起草人）

**设计文档 §11.1 需要的服务端改动**（P4 起阻塞）：
- `GET /api/conversations/:id/messages` 加 `?limit=1..50` querystring；SQL 把 `LIMIT 50` 改成 `LIMIT $3`
- 必须在 P4 开工前 **先提交服务端 PR** 并合入，否则 §5.3 场景 C / 上滑本地优先拉取无法实现

**P2 会触及本阶段的文件**：
- `AppContainer.bootstrap()` 目前拿到 token 后只填占位 `currentUser`；P2 要改成调 `GET /api/users/me` 回真实用户，并在失败（401）时清 Keychain + 保持未登录态。登录态判定也应该挪到 `UserSession`（P3 引入）
- `AuthRepository` 在 P3 会多出 `handleUnauthorized()`（WS 401 / REST 401 时调）

**P3 引入 `UserSession`**：
- 所有 WS / SwiftData 绑在 `UserSession`；`AppContainer.currentUser` 属性让位给 `AppContainer.session: UserSession?`
- 登出流程升级为设计文档 §2.2 / §5.5 的三阶段 teardown

**Nuke 首次真正使用在 P2**（头像 `LazyImage`）；本阶段只引入 SPM，未 import。
