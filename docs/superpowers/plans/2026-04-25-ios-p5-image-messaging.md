# iOS P5 实施计划：图片消息

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `ios-app/` 从 P4 的"文字消息 + 实时 WS + SwiftData 本地缓存"推进到"能从相册挑图、按服务端契约（1600px / JPEG 0.80 / 白底 flatten）压缩后两步上传发送、失败按 `ImageSendStage` 阶段化重试（已上传过的不再重传）、收到对方图片走 Nuke 加载、点击进入全屏预览"——对应设计文档第 8 节的 P5 阶段 + §6 全章节。

**Architecture:** 三件事并行展开：

1. **iOS 网络层**：新增 `UploadRepository`（multipart 上传 `POST /api/upload/message-image`）、`MessageRepository.sendImage`（POST `/api/messages` 带 `media_url` + `message_type:"image"` + `client_temp_id`），与现有 `MessageRepository.sendText` 对称。两者复用 `APIClient`，但 multipart 路径需要在 `APIClient` 上扩一个 `upload(_:boundary:body:token:)` 方法（不影响 JSON 路径）。

2. **iOS 业务层**：新增 `ImageCompressor`（设计 §6.2，先白底 flatten 再 1600px / JPEG 0.80）、`ImageSendStage` 枚举（设计 §6.3：`.notStarted` / `.uploaded(mediaURL:)`），`ChatViewModel` 增加 `imageSendStages: [String: ImageSendStage]`、`sendImage(_:)`、把 `retry(localId:)` 按 `messageType` 分叉。`UserSession` 新增 `makeUploadRepository()` 与 `makeMessageRepository()` 对称的工厂方法。

3. **iOS UI 层**：新增 `ImageMessageBubble`（设计 §6.4，`localImageData` 优先，回退到 Nuke 远程加载）、`Lightbox`（设计 §6.5 全屏 pinch/zoom）；`MessageBubble` 按 `messageType` 派发 text 或 image bubble；`ChatView` 输入栏左侧加 `PhotosPicker` 按钮，选图后 `loadTransferable(type: Data.self)` 解码出 `UIImage` 喂给 `vm.sendImage(_:)`。

**Tech Stack:** SwiftUI、Swift Concurrency、`PhotosUI.PhotosPicker`、`UIGraphicsImageRenderer`（白底 flatten）、`URLSession.data(for:)` + 手写 `multipart/form-data` 字节流（不用 `upload(for:from:)`，原因见 Task 2）、Nuke + NukeUI（已在项目里）、Swift Testing、XCUITest。

**TDD 适用范围（与 P1/P2/P3/P4 一致）：**

- **纯逻辑 → TDD**：`ImageCompressor` 输出尺寸 + 白底像素验证；`UploadRepository` multipart body 形状（boundary、CRLF、`name="file"`、`Content-Type: image/jpeg`）；`MessageRepository.sendImage` 请求体 / 路径；`ChatViewModel.sendImage` 状态机（compress 失败 / 上传失败 / 发送失败三条分叉）+ `retry` 跳过上传路径。
- **View / Picker / 全屏预览 → 编译 + XCUITest smoke + 模拟器手工**：`ImageMessageBubble` localData / 远程切换；`Lightbox` pinch/zoom；`PhotosPicker` 弹出（系统 UI 不可 XCUITest 触达，仅断言"按钮可点击 + Picker 出现"）。

**服务端契约改动：** 无。`POST /api/upload/message-image` 已经在 `server/src/routes/upload.ts:109` 实现，`POST /api/messages` 的 `message_type:'image'` + `media_url` 验证在 `server/src/routes/messages.ts:36-46`，`server/tests/upload.test.ts:250` 与 `server/tests/messages.test.ts` 已覆盖。**P5 不开 server task**——本计划里出现的所有命令都不应改 `server/` 任何文件。

**不在 P5 范围（明确延后）：**
- **Presence + Typing 的 UI 响应** → P6；P5 不增加新的 WS 事件类型，`PresenceStore` / `TypingStore` 还停留在 P4 的占位实现。
- **Profile 编辑 + 头像上传** → P7；P7 会复用 P5 的 `UploadRepository`（再加 `uploadAvatar(data:token:)` 方法，参数对齐 `AVATAR_CONFIG`），但在 P5 只暴露图片消息一条上传路径。
- **图片宽高占位字段**：服务端 Message 不带 width/height（设计 §6.5 已知限制）。P5 占位用 4:3，加载完后按真实比例重排，**不**改服务端 schema、**不**给 `CachedMessage` 加新字段（避免触发首次 SwiftData migration，P4 self-review 已明确延后）。
- **本地 image 拍照入口**：P5 只接 `PhotosPicker`（相册）；`UIImagePickerController` 拍照路径下次再说。
- **图片消息撤回 / 删除 / 单图多选**：服务端目前不支持单条删除。
- **Lightbox 翻页（左右滑切换图片）**：作品集范围只做"点开看 + pinch/zoom + 关闭"，不做画廊。

**已知妥协：**
- **VM 重建后 failed 图片消息丢失**：图片消息的 pending bubble + `localImageData` 都只存在内存里（缓存只写 confirmed 消息）。用户在 ChatView 处于 failed 态时切到联系人 / 切到其他会话再回来，`ChatViewModel` 重建会丢掉这条 pending；用户必须重新选图。文字消息也是同样行为，但文字内容用户能记住、图片用户不一定。**取舍**：选 A（重建后丢失，需用户重选）而不是 B（在 SwiftData 加 placeholder + 长期失败状态），理由是 B 会污染连续后缀不变式且与"messageType=image 必须有 media_url"的服务端 CHECK 约束不一致。
- **`writeThroughAndMeta` 不写 pending image**：与 P4 一致；只在服务端 201 / WS echo 回来后落 SwiftData，pending 占位（id 负、`media_url` nil）会破坏 §5.2 不变式。
- **压缩在主线程**：`ImageCompressor.compressForUpload` 通过 `UIGraphicsImageRenderer` 重绘 + `jpegData(compressionQuality:)`，主线程同步执行。1600px JPEG 0.80 的耗时实测 < 200ms，不至于造成卡顿；如果以后体感卡顿再迁到 `Task.detached`。注意 `UIImage` 不是 Sendable，迁移时要先把 `Data` 解码出来传过去。
- **上传无进度回调**：`UploadRepository` 用 `URLSession.data(for:)` + `request.httpBody = multipartBody` 一次性上传（实现细节见 Task 2），不监听 `URLSessionTaskDelegate.didSendBodyData`。bubble 上只显示 `pending` spinner、不显示百分比；作品集场景 1600px / JPEG 0.80 平均 < 300KB，4G 网络上 1-2 秒搞定。P8 加进度条时再迁到 `upload(for:from:)` + `URLSessionTaskDelegate`。
- **Lightbox 不持久化缩放比例**：每次进入都重置到 fit。
- **图片预览首次抖动**：服务端 Message 不带宽高，`LazyImage` 用 4:3 占位，加载完后按真实比例重排。设计 §6.5 已知限制。

**重要不变式（实现前必须读懂，实现中容易踩到）：**

1. **media_url 不要客户端拼**：`ChatViewModel.sendImage` 必须用 `UploadRepository.uploadMessageImage` 的返回值原样传给 `MessageRepository.sendImage`。服务端 `messages.ts:42` 用正则 `^/uploads/messages/{senderId}-\d{10,16}\.jpg$` 校验，自己拼路径会被 400。
2. **multipart field name 必须是 `file`**：与 Web 端 `client/src/lib/api.ts:61` `formData.append('file', blob, 'image.jpg')` 对齐。服务端 `fastify-multipart` 默认按字段名找文件 part；写错了拿不到 `file`，返回 400 "No file provided"。
3. **白底 flatten 必须先于 resize**：与服务端 `sharp.flatten({ r:255, g:255, b:255 }).resize(...)` 顺序一致。`UIGraphicsImageRenderer` 里先 `setFill(.white) → fill(rect) → image.draw(in:)`，反过来透明像素会落黑底。
4. **`UIGraphicsImageRendererFormat.scale = 1`**：默认 scale 跟设备 density（@2x/@3x）走，会输出 3200x3200 像素的"1600pt"图，比服务端期望大 9 倍。设计 §6.2 已强调。
5. **`mergeServerResult` 保留 `localImageData`**：`ChatViewModel.swift:276` 现有实现已经做对，**P5 不要修改这一行**——它是不闪烁的关键。
6. **pending image 不写 SwiftData**：与 P4 self-review 第 6 条一致；`writeThroughAndMeta` 只在 `mergeServerResult` 与 `handleIncomingMessage` 的 confirmed 路径调用。

---

## 开发环境前提

沿用 P1/P2/P3/P4。命令约定：

```bash
# iOS 编译（Debug）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# iOS 单测（Swift Testing）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMTests

# iOS XCUITest（smoke）
xcodebuild -project ios-app/EchoIM.xcodeproj \
  -scheme EchoIM \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test -only-testing:EchoIMUITests
```

服务端不动，但仍需保证现有 upload / messages 测试通过：

```bash
npm test --prefix server -- upload messages
```

工作目录约定：所有 iOS 路径以 `ios-app/EchoIM/` 开头；所有任务里出现的 `xcodebuild ... build` 与 `... test` 命令隐含 `-project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15'`，下方 Step 里直接写 `$BUILD` / `$TEST` / `$UITEST` 占位。

---

## 文件结构

新增文件：

```
ios-app/EchoIM/
├── Core/
│   ├── Networking/
│   │   └── APIClient+Upload.swift          // 新：APIClient 的 multipart 扩展
│   ├── Utilities/
│   │   └── ImageCompressor.swift           // 新：UIImage → (Data, w, h)
│   └── UI/
│       └── ZoomableImageView.swift         // 新：UIScrollView wrap，pinch/zoom
└── Features/
    ├── Chat/
    │   ├── ImageMessageBubble.swift        // 新：localData / 远程切换
    │   ├── Lightbox.swift                  // 新：全屏预览 sheet
    │   ├── ImageSendStage.swift            // 新：阶段化重试枚举
    │   └── UploadRepository.swift          // 新：上传抽象
ios-app/EchoIMTests/
├── ImageCompressorTests.swift              // 新
├── UploadRepositoryTests.swift             // 新
├── MessageRepositorySendImageTests.swift   // 新（与 MessageRepositoryTests 分文件，避免 P3 的文件继续膨胀）
├── ImageTestHelpers.swift                  // 新：图片发送相关测试共享 mock/helper
├── ChatViewModelImageTests.swift           // 新（与 ChatViewModelSendTests 分文件，独立场景）
└── ImageSendStageTests.swift               // 新：枚举/转换的最小契约
ios-app/EchoIMUITests/
└── ImageSendSmokeTests.swift               // 新
```

修改文件：

```
ios-app/EchoIM/
├── App/
│   └── UserSession.swift                   // +makeUploadRepository()
├── Core/
│   └── Networking/APIClient.swift          // 让 session 对 APIClient+Upload extension 可见
├── Features/
│   ├── Chat/
│   │   ├── ChatRoute.swift                 // 不动
│   │   ├── ChatView.swift                  // +PhotosPicker、+uploadRepo 注入
│   │   ├── ChatViewModel.swift             // +sendImage / retry 分叉 / +uploadRepo / +imageSendStages
│   │   ├── LocalMessage.swift              // 不动（localImageData P4 已预留）
│   │   ├── MessageBubble.swift             // 按 messageType 派发
│   │   └── MessageRepository.swift         // +sendImage(...)
│   └── Conversations/
│       └── ConversationsListView.swift     // 不动（"[图片]"预览 P4 已就位，仅在 Task 12 验证一次）
└── App/
    └── AppContainer.swift                  // 不动（UploadRepository 挂在 UserSession）
```

每个文件单一职责。`Lightbox` 与 `ZoomableImageView` 拆开是因为 SwiftUI 没有内置 pinch/zoom，UIKit `UIScrollView.minimumZoomScale = 1` + `maximumZoomScale = 4` + `UIViewRepresentable` 是最稳的实现，单独成文件后续 Profile 头像点开预览也能复用。

---

## Task 1: ImageCompressor — 白底 flatten + 1600px / JPEG 0.80

**Files:**
- Create: `ios-app/EchoIM/Core/Utilities/ImageCompressor.swift`
- Test: `ios-app/EchoIMTests/ImageCompressorTests.swift`

设计依据：§6.2。白底必须在 resize 之前 fill，避免与服务端 `sharp.flatten({ r:255, g:255, b:255 })` 行为不一致。`UIGraphicsImageRendererFormat.scale = 1` 是关键——默认会按 device scale（@2x/@3x）放大像素，使输出实际是 4800x4800 而不是 1600x1600。

- [x] **Step 1: 写测试 — 透明 PNG 压缩后第一像素是白色**

```swift
// ios-app/EchoIMTests/ImageCompressorTests.swift
import Testing
import UIKit
@testable import EchoIM

@Suite
struct ImageCompressorTests {
    @Test
    func transparentInputBecomesWhiteBackgroundJPEG() throws {
        let transparent = makeTransparentPNG(size: CGSize(width: 200, height: 200))
        let result = try #require(ImageCompressor.compressForUpload(transparent))

        #expect(result.width == 200)
        #expect(result.height == 200)

        // JPEG 不支持透明；解码出来必须是白底（≈ 255, 255, 255），不能是黑底（0, 0, 0）
        let decoded = try #require(UIImage(data: result.data))
        let pixel = readFirstPixel(decoded)
        #expect(pixel.r > 250)
        #expect(pixel.g > 250)
        #expect(pixel.b > 250)
    }

    @Test
    func resizesLongerEdgeTo1600WhenLarger() throws {
        let big = makeOpaqueImage(size: CGSize(width: 4000, height: 2000), color: .red)
        let result = try #require(ImageCompressor.compressForUpload(big))

        // 长边 = 1600，短边按比例 = 800
        #expect(result.width == 1600)
        #expect(result.height == 800)
    }

    @Test
    func keepsOriginalDimensionsWhenSmaller() throws {
        let small = makeOpaqueImage(size: CGSize(width: 600, height: 400), color: .blue)
        let result = try #require(ImageCompressor.compressForUpload(small))

        // 不放大；保持原尺寸
        #expect(result.width == 600)
        #expect(result.height == 400)
    }

    @Test
    func outputIsJPEGUnderTenMB() throws {
        let big = makeOpaqueImage(size: CGSize(width: 4000, height: 4000), color: .green)
        let result = try #require(ImageCompressor.compressForUpload(big))

        // 服务端 multipart 上限 10MB；1600x1600 / Q80 实测 < 1MB
        #expect(result.data.count < 10 * 1024 * 1024)
        // JPEG SOI 魔数
        #expect(result.data.starts(with: [0xFF, 0xD8]))
    }

    // MARK: - Helpers

    private struct RGB { let r: UInt8; let g: UInt8; let b: UInt8 }

    private func makeTransparentPNG(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            // 不填充，保留透明
        }
    }

    private func makeOpaqueImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func readFirstPixel(_ image: UIImage) -> RGB {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return RGB(r: 0, g: 0, b: 0)
        }
        // 假设 RGBA / RGB；只读前 3 字节
        return RGB(r: bytes[0], g: bytes[1], b: bytes[2])
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/ImageCompressorTests`
Expected: 编译失败（`ImageCompressor` 未定义）。

- [x] **Step 3: 实现 ImageCompressor**

```swift
// ios-app/EchoIM/Core/Utilities/ImageCompressor.swift
import UIKit

/// 与服务端 MESSAGE_IMAGE_CONFIG（1600 / JPEG 0.80 / 白底 flatten）完全对齐。
/// 不放大小图，长边超过 1600 才按比例缩放。
enum ImageCompressor {
    /// 设计 §6.2。返回 `nil` 表示编码失败（极端 OOM / 损坏数据）；
    /// 调用方应当作发送失败处理。
    static func compressForUpload(_ image: UIImage) -> (data: Data, width: Int, height: Int)? {
        let maxDim: CGFloat = 1600
        let scale = min(1.0, maxDim / max(image.size.width, image.size.height))
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        // opaque + 显式 scale=1 是关键。前者保证 alpha 通道被丢弃（透明像素落白底），
        // 后者保证输出像素 = pt 数（不被 device @2x/@3x 放大）。
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = resized.jpegData(compressionQuality: 0.80) else {
            return nil
        }
        return (data, Int(targetSize.width), Int(targetSize.height))
    }
}
```

- [x] **Step 4: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ImageCompressorTests`
Expected: 4 个测试全过。第一像素 R/G/B 都应该 > 250。

验证记录：本机没有 `OS:latest` 的 iPhone 15 目标，使用
`-destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15'` 跑通 4 个测试。

- [x] **Step 5: 提交**

```bash
git add ios-app/EchoIM/Core/Utilities/ImageCompressor.swift \
         ios-app/EchoIMTests/ImageCompressorTests.swift
git commit -m "feat(ios): add ImageCompressor with white-fill flatten"
```

---

## Task 2: APIClient multipart 扩展

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/APIClient+Upload.swift`
- Modify: `ios-app/EchoIM/Core/Networking/APIClient.swift`（仅给 `session` 改成 `internal` 让 extension 能访问；如果已经是 `internal`，跳过）

设计依据：multipart 路径不能复用 JSON `request(_:method:token:body:)`——后者把 `body` JSON 编码成 `application/json`。新增一个 `upload<Response>(_:boundary:body:token:)`，复用现有 status / decoder 处理。

> **关键实现选择**：内部用 `request.httpBody = body` + `session.data(for:)` 而不是 `session.upload(for:from:)`。后者 `URLSession` 会把 body 转成 stream，`MockURLProtocol` 在 `startLoading()` 里只能拿到 `request.httpBodyStream` 不能拿到 `request.httpBody`，测试断言 body 内容时会很麻烦。直接走 `data(for:)` 让 body 留在 `request.httpBody`，单测用 `req.httpBody` 即可读到完整 multipart 字节。multipart 上限 10MB（服务端 `MAX_FILE_SIZE`），全装内存没问题。

- [x] **Step 1: 写测试 — multipart 请求形状（用现有 MockURLProtocol.configure 风格）**

```swift
// ios-app/EchoIMTests/APIClientUploadTests.swift  ← Task 3 会删除本文件，由 UploadRepositoryTests 接管
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("APIClient — Upload")
struct APIClientUploadTests {
    @Test
    func uploadSendsMultipartWithFileFieldAndBearer() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { req in
            capturedRequest = req
            let body = """
            {"media_url":"/uploads/messages/42-1234567890.jpg"}
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let api = APIClient(session: URLSession(configuration: config))

        let body = Self.makeBody(boundary: "TestBoundary", payload: Data([0xFF, 0xD8, 0xFF]))
        let response: APIClientUploadProbe = try await api.upload(
            "api/upload/message-image",
            boundary: "TestBoundary",
            body: body,
            token: "abc"
        )

        #expect(response.mediaUrl == "/uploads/messages/42-1234567890.jpg")

        let req = try #require(capturedRequest)
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let contentType = try #require(req.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType == "multipart/form-data; boundary=TestBoundary")

        // body 在 httpBody 上（实现选了 data(for:) 而不是 upload(for:from:)，避免 stream）
        let captured = try #require(req.httpBody)
        let bodyString = String(decoding: captured, as: UTF8.self)
        // field name 必须是 file，与服务端 fastify-multipart 默认期望一致
        #expect(bodyString.contains("name=\"file\""))
        #expect(bodyString.contains("filename=\"image.jpg\""))
        #expect(bodyString.contains("Content-Type: image/jpeg"))
    }

    @Test
    func uploadMaps401ToUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Unauthorized\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))

        do {
            let _: APIClientUploadProbe = try await api.upload(
                "api/upload/message-image",
                boundary: "X",
                body: Self.makeBody(boundary: "X", payload: Data([0xFF, 0xD8])),
                token: "stale"
            )
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
    }

    @Test
    func uploadMapsNon2xxToHTTPStatus() async throws {
        let (config, _) = MockURLProtocol.configure { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Invalid image file\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))

        do {
            let _: APIClientUploadProbe = try await api.upload(
                "api/upload/message-image",
                boundary: "X",
                body: Self.makeBody(boundary: "X", payload: Data([0x00])),
                token: "tok"
            )
            Issue.record("expected APIError.http")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    private static func makeBody(boundary: String, payload: Data) -> Data {
        var data = Data()
        let crlf = "\r\n"
        data.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\(crlf)".data(using: .utf8)!)
        data.append("Content-Type: image/jpeg\(crlf)\(crlf)".data(using: .utf8)!)
        data.append(payload)
        data.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return data
    }
}

/// 私有探测类型，与 UploadRepository 内部 response 同形状。Task 3 删除本文件时一并删。
private struct APIClientUploadProbe: Decodable {
    let mediaUrl: String
}
```

实现记录：本仓库 `APIClient.jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase`，
因此测试探测类型不声明 `CodingKeys`，让 `media_url` 自动映射到 `mediaUrl`。
另外，`URLProtocol` 捕获到的请求体在本机仍可能落到 `httpBodyStream`，测试 helper 会先读
`httpBody`，为空时再读取 stream。

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/APIClientUploadTests`
Expected: 编译失败（`APIClient.upload(_:boundary:body:token:)` 未定义）。

- [x] **Step 3: 实现 APIClient.upload**

```swift
// ios-app/EchoIM/Core/Networking/APIClient+Upload.swift
import Foundation

extension APIClient {
    /// multipart/form-data 上传。与 `request(_:method:token:body:)` 共享 status code 处理 / decoder。
    /// 不复用 `request` 是因为后者会把 body 当 JSON 编码并强行覆盖 Content-Type。
    /// 内部用 `data(for:)` 而不是 `upload(for:from:)`：后者会把 body 转成 stream，
    /// `MockURLProtocol` 拿不到 `request.httpBody`，测试断言 body 形状会很麻烦；
    /// multipart 上限 10MB（服务端 `MAX_FILE_SIZE`），全装内存没问题。
    func upload<Response: Decodable>(
        _ path: String,
        boundary: String,
        body: Data,
        token: String
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: Endpoints.baseURL)?.absoluteURL else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.fromStatus(http.statusCode, body: data)
        }

        do {
            return try Self.jsonDecoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
```

> 这里需要让 `APIClient.session` 对 extension 可见。检查命令：
> ```bash
> grep -n "session" ios-app/EchoIM/Core/Networking/APIClient.swift | head
> ```
> 如果输出里看到 `private let session`，把 `private` 改成 `internal`（或删掉，默认就是 internal）。当前 P1 的实现是 `private let session: URLSession`，必须改。

- [x] **Step 4: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/APIClientUploadTests`
Expected: 3 个测试通过。

- [x] **Step 5: lint + build**

Run: `$BUILD`
Expected: SUCCEEDED。

- [x] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Core/Networking/APIClient+Upload.swift \
         ios-app/EchoIM/Core/Networking/APIClient.swift \
         ios-app/EchoIMTests/APIClientUploadTests.swift
git commit -m "feat(ios): add APIClient multipart upload"
```

---

## Task 3: UploadRepository — 把 multipart 细节封住

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/UploadRepository.swift`
- Create: `ios-app/EchoIMTests/UploadRepositoryTests.swift`
- Delete: `ios-app/EchoIMTests/APIClientUploadTests.swift`（Task 2 的过渡测试，UploadRepository 上线后由它接管）

`UploadRepository` 是给 `ChatViewModel` 看到的"喂 Data，收 mediaURL"接口。multipart 拼装、boundary 生成、JSON 解码都封在 impl 内部；测试都从 `UploadRepository` 这一层进入。

- [x] **Step 1: 写 protocol + 测试（用现有 MockURLProtocol.configure 风格）**

```swift
// ios-app/EchoIMTests/UploadRepositoryTests.swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("UploadRepository")
struct UploadRepositoryTests {
    @Test
    func uploadMessageImageReturnsMediaURL() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { req in
            capturedRequest = req
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{\"media_url\":\"/uploads/messages/7-1745800000000.jpg\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        let url = try await repo.uploadMessageImage(
            data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            token: "tok"
        )
        #expect(url == "/uploads/messages/7-1745800000000.jpg")

        let req = try #require(capturedRequest)
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path == "/api/upload/message-image")
        let contentType = try #require(req.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.starts(with: "multipart/form-data; boundary="))

        let body = try #require(req.httpBody)
        let bodyText = String(decoding: body, as: UTF8.self)
        // field name 必须是 file，与服务端 fastify-multipart 默认期望对齐
        #expect(bodyText.contains("name=\"file\""))
        #expect(bodyText.contains("filename=\"image.jpg\""))
        #expect(bodyText.contains("Content-Type: image/jpeg"))
    }

    @Test
    func uploadMessageImagePropagatesUnauthorized() async throws {
        let (config, _) = MockURLProtocol.configure { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Unauthorized\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadMessageImage(data: Data([0xFF, 0xD8]), token: "tok")
            Issue.record("expected APIError.unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
    }

    @Test
    func uploadMessageImageMaps400ToHTTPStatus() async throws {
        let (config, _) = MockURLProtocol.configure { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Invalid image file\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        do {
            _ = try await repo.uploadMessageImage(data: Data([0x00]), token: "tok")
            Issue.record("expected APIError.http")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }

    @Test
    func boundaryIsUniquePerCall() async throws {
        // MockURLProtocol.configure 的 handler 闭包是共享 actor 边界外的捕获，需要 lock 保护。
        // 这里用 NSLock + Array 简单同步两次调用的 boundary。
        nonisolated(unsafe) var boundaries: [String] = []
        let lock = NSLock()
        let (config, _) = MockURLProtocol.configure { req in
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            // "multipart/form-data; boundary=Boundary-..."
            let boundary = String(contentType.split(separator: "=").last ?? "")
            lock.lock()
            boundaries.append(boundary)
            lock.unlock()
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                "{\"media_url\":\"/uploads/messages/1-1.jpg\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = UploadRepositoryImpl(api: api)

        _ = try await repo.uploadMessageImage(data: Data([0xFF]), token: "t")
        _ = try await repo.uploadMessageImage(data: Data([0xFF]), token: "t")

        lock.lock()
        let recorded = boundaries
        lock.unlock()
        #expect(recorded.count == 2)
        #expect(recorded[0] != recorded[1], "每次调用必须用新的 boundary，避免请求间字节窜流")
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/UploadRepositoryTests`
Expected: 编译失败（`UploadRepository` / `UploadRepositoryImpl` 未定义）。

- [x] **Step 3: 实现 UploadRepository**

```swift
// ios-app/EchoIM/Features/Chat/UploadRepository.swift
import Foundation

protocol UploadRepository {
    /// 把已经压缩好的 JPEG 字节流上传到 `/api/upload/message-image`，
    /// 返回服务端分配的 `media_url`（`/uploads/messages/<senderId>-<unix-ms>.jpg`）。
    /// 调用方必须把这个字符串原样传给 `MessageRepository.sendImage(...)`，
    /// 自己拼路径会被服务端 `messages.ts:42` 正则 400。
    func uploadMessageImage(data: Data, token: String) async throws -> String
}

private struct UploadMessageImageResponse: Decodable {
    let mediaUrl: String
}

@MainActor
final class UploadRepositoryImpl: UploadRepository {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.makeMultipartBody(
            fieldName: "file",
            filename: "image.jpg",
            contentType: "image/jpeg",
            payload: data,
            boundary: boundary
        )

        let response: UploadMessageImageResponse = try await api.upload(
            Endpoints.Upload.messageImage,
            boundary: boundary,
            body: body,
            token: token
        )
        return response.mediaUrl
    }

    /// RFC 2046 multipart/form-data。CRLF 边界要严格按规范，少一个就 400。
    /// fieldName 必须与服务端 fastify-multipart 期望对齐（消息图是 `file`）。
    private static func makeMultipartBody(
        fieldName: String,
        filename: String,
        contentType: String,
        payload: Data,
        boundary: String
    ) -> Data {
        let crlf = "\r\n"
        var body = Data()
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\(crlf)"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(contentType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(payload)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }
}
```

并在 `Endpoints` 增加路径：

```swift
// ios-app/EchoIM/Core/Networking/Endpoints.swift
// 注意：Upload 是 Endpoints 的嵌套 enum——必须写在 `enum Endpoints { ... }` 内部，
// 在 `enum Messages { static let base = "api/messages" }` 之后、Endpoints 闭合 `}` 之前。
// 调用处是 Endpoints.Upload.messageImage，不是顶层 Upload.messageImage。
enum Endpoints {
    // ... 现有 baseURL / url(_:) / absolute(_:) / webSocketURL(token:) 不变
    // ... 现有 enum Auth / Users / Friends / FriendRequests / Conversations / Messages 不变

    enum Upload {
        static let messageImage = "api/upload/message-image"
        // P7 会在这里加 avatar
    }
}
```

实现记录：`UploadMessageImageResponse` 不声明 `CodingKeys`，继续复用
`APIClient.jsonDecoder` 的 `.convertFromSnakeCase`。测试读取 multipart body 时同 Task 2，
兼容 `httpBody` 与 `httpBodyStream`。

- [x] **Step 4: 删除 Task 2 的过渡测试（UploadRepository 已经覆盖同样契约）**

```bash
git rm ios-app/EchoIMTests/APIClientUploadTests.swift
```

- [x] **Step 5: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/UploadRepositoryTests`
Expected: 4 个测试通过。

- [x] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/UploadRepository.swift \
         ios-app/EchoIM/Core/Networking/Endpoints.swift \
         ios-app/EchoIMTests/UploadRepositoryTests.swift
git commit -m "feat(ios): add UploadRepository with multipart message-image"
```

---

## Task 4: MessageRepository.sendImage

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/MessageRepository.swift`
- Create: `ios-app/EchoIMTests/MessageRepositorySendImageTests.swift`

服务端 `messages.ts:14-19` 的 schema：
```json
{ "recipient_id": int, "client_temp_id": str, "message_type": "image", "media_url": str }
```

`media_url` 必须形如 `/uploads/messages/<senderId>-\d{10,16}\.jpg`，由 `UploadRepository.uploadMessageImage` 返回，原样传。客户端不再做格式检查（让服务端 400 自然抛出）。

- [x] **Step 1: 写测试 — sendImage 请求体形状**

> **APIError 现状**（`APIError.swift:3`）：只有 `network/unauthorized/http(status:body:)/decoding/invalidResponse`。401 走 `.unauthorized`，其它非 2xx 走 `.http(status:body:)`。下面所有 4xx 测试都用 `case APIError.http(let status, _)` 模式匹配。

```swift
// ios-app/EchoIMTests/MessageRepositorySendImageTests.swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("MessageRepository — sendImage")
struct MessageRepositorySendImageTests {
    @Test
    func sendImagePostsExpectedJSONBody() async throws {
        var capturedRequest: URLRequest?
        let (config, _) = MockURLProtocol.configure { req in
            capturedRequest = req
            let body = """
            {
              "id": 101,
              "conversation_id": 5,
              "sender_id": 3,
              "body": null,
              "message_type": "image",
              "media_url": "/uploads/messages/3-1745800000000.jpg",
              "created_at": "2026-04-25T10:00:00.000Z",
              "client_temp_id": "tmp-img-1"
            }
            """.data(using: .utf8)!
            return (
                HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                body
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = MessageRepositoryImpl(api: api)

        let result = try await repo.sendImage(
            recipientId: 9,
            mediaUrl: "/uploads/messages/3-1745800000000.jpg",
            clientTempId: "tmp-img-1",
            token: "tok"
        )

        #expect(result.id == 101)
        #expect(result.messageType == "image")
        #expect(result.mediaUrl == "/uploads/messages/3-1745800000000.jpg")
        #expect(result.clientTempId == "tmp-img-1")

        let req = try #require(capturedRequest)
        #expect(req.httpMethod == "POST")
        #expect(req.url?.path == "/api/messages")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(req.httpBody)
        let parsed = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        #expect(parsed?["recipient_id"] as? Int == 9)
        #expect(parsed?["media_url"] as? String == "/uploads/messages/3-1745800000000.jpg")
        #expect(parsed?["message_type"] as? String == "image")
        #expect(parsed?["client_temp_id"] as? String == "tmp-img-1")
        #expect(parsed?["body"] == nil, "image 消息不应带 body 字段")
    }

    @Test
    func sendImagePropagates403WhenNotFriends() async throws {
        let (config, _) = MockURLProtocol.configure { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Not friends\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = MessageRepositoryImpl(api: api)

        do {
            _ = try await repo.sendImage(
                recipientId: 9,
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                clientTempId: "tmp",
                token: "tok"
            )
            Issue.record("expected APIError.http(403)")
        } catch APIError.http(let status, _) {
            #expect(status == 403)
        }
    }

    @Test
    func sendImagePropagates400WhenInvalidMediaURL() async throws {
        let (config, _) = MockURLProtocol.configure { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                "{\"error\":\"Invalid media_url\"}".data(using: .utf8)!
            )
        }
        let api = APIClient(session: URLSession(configuration: config))
        let repo = MessageRepositoryImpl(api: api)

        do {
            _ = try await repo.sendImage(
                recipientId: 9,
                mediaUrl: "/wrongprefix/abc.jpg",
                clientTempId: "tmp",
                token: "tok"
            )
            Issue.record("expected APIError.http(400)")
        } catch APIError.http(let status, _) {
            #expect(status == 400)
        }
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/MessageRepositorySendImageTests`
Expected: 编译失败（`MessageRepository.sendImage` 未定义）。

- [x] **Step 3: 在 `MessageRepository` 协议加 sendImage**

```swift
// ios-app/EchoIM/Features/Chat/MessageRepository.swift
// 在协议里追加：
protocol MessageRepository {
    // ... 现有 list / sendText / markRead 不变
    func sendImage(
        recipientId: Int,
        mediaUrl: String,
        clientTempId: String,
        token: String
    ) async throws -> Message
}

// 在文件 private struct 区域增加：
private struct SendImageBody: Encodable {
    let recipientId: Int
    let mediaUrl: String
    let messageType: String
    let clientTempId: String

    enum CodingKeys: String, CodingKey {
        case recipientId = "recipient_id"
        case mediaUrl = "media_url"
        case messageType = "message_type"
        case clientTempId = "client_temp_id"
    }
}

// 在 MessageRepositoryImpl 的 markRead 之前追加：
extension MessageRepositoryImpl {
    func sendImage(
        recipientId: Int,
        mediaUrl: String,
        clientTempId: String,
        token: String
    ) async throws -> Message {
        try await api.request(
            Endpoints.Messages.base,
            method: "POST",
            token: token,
            body: SendImageBody(
                recipientId: recipientId,
                mediaUrl: mediaUrl,
                messageType: "image",
                clientTempId: clientTempId
            )
        )
    }
}
```

> 注意把 `extension MessageRepositoryImpl` 直接写在原 final class 同文件下方即可（同样的 `@MainActor` 在 class 上声明，extension 自动继承）。如果 lint 不喜欢两段，可以把 `sendImage` 直接挂到 class 内 `markRead` 之前。

- [x] **Step 4: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/MessageRepositorySendImageTests`
Expected: 3 个测试通过。

- [x] **Step 5: 检查 P3 已有的 mock**

P3 / P4 的测试里有若干 `MessageRepository` mock，比如 `ChatViewModelSendTests` 的 `class`、`ChatViewModelCacheTests` 的 `actor BlockingRepo` / `actor PagedRepo` / `actor StrictRepo` / `actor RecordingRepo` 等。新增协议方法会让这些 mock 编译失败。**用包含 actor / struct 的 grep**：

```bash
grep -rEn "(class|actor|struct).*: MessageRepository|MockMessageRepo" ios-app/EchoIMTests
```

对每个 mock，加一个最简实现（默认 throw "not implemented"），后续 Task 5 再让 ChatViewModelImageTests 用专门的 mock：

```swift
func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
    throw NSError(domain: "MockNotImpl", code: 0)
}
```

- [x] **Step 6: 编译 + 跑全量测试，确认 P3/P4 测试不退化**

Run: `$TEST -only-testing:EchoIMTests`
Expected: 全部通过。

实现记录：`MessageRepositorySendImageTests` 读取 JSON 请求体时同上传测试一样兼容
`httpBody` / `httpBodyStream`；本机全量 `EchoIMTests` 使用
`-destination 'platform=iOS Simulator,OS=17.5,name=iPhone 15'` 跑通。

- [x] **Step 7: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/MessageRepository.swift \
         ios-app/EchoIMTests/MessageRepositorySendImageTests.swift \
         ios-app/EchoIMTests/ChatViewModelSendTests.swift \
         ios-app/EchoIMTests/ChatViewModelCacheTests.swift \
         ios-app/EchoIMTests/ChatViewModelLoadTests.swift \
         ios-app/EchoIMTests/ChatViewModelWSTests.swift \
         ios-app/EchoIMTests/ChatViewModelReadTests.swift \
         ios-app/EchoIMTests/MessageRepositoryTests.swift
git commit -m "feat(ios): add MessageRepository.sendImage"
```

> 实际 git add 列表以 `git status` 输出为准；P4 的 mock 散在多个文件，Step 5 的 grep 帮你确认。

---

## Task 5: ImageSendStage 枚举 + ChatViewModel 注入 UploadRepository

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/ImageSendStage.swift`
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Create: `ios-app/EchoIMTests/ImageSendStageTests.swift`

设计依据：§6.3。`ImageSendStage` 是为了让重试**不重复上传**而存在的最小 state；只有两个值（其它都用 `LocalMessage.sendState` 表达）：
- `.notStarted` — 还没成功上传过；retry 时需要重新走 compress + upload + send 全链路
- `.uploaded(mediaURL:)` — 已经上传成功但发消息那一步失败；retry 时跳过 upload，直接发消息

- [x] **Step 1: 写枚举 + 最小契约测试**

```swift
// ios-app/EchoIMTests/ImageSendStageTests.swift
import Testing
@testable import EchoIM

@Suite
struct ImageSendStageTests {
    @Test
    func equalityIgnoresAssociatedValueOnNotStarted() {
        #expect(ImageSendStage.notStarted == .notStarted)
    }

    @Test
    func uploadedEqualityChecksMediaURL() {
        let a = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg")
        let b = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg")
        let c = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-2.jpg")
        #expect(a == b)
        #expect(a != c)
        #expect(a != .notStarted)
    }

    @Test
    func uploadedExtractsMediaURL() {
        let stage = ImageSendStage.uploaded(mediaURL: "/uploads/messages/1-1.jpg")
        if case .uploaded(let url) = stage {
            #expect(url == "/uploads/messages/1-1.jpg")
        } else {
            Issue.record("expected uploaded case")
        }
    }
}
```

- [x] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/ImageSendStageTests`
Expected: 编译失败（`ImageSendStage` 未定义）。

- [x] **Step 3: 实现 ImageSendStage**

```swift
// ios-app/EchoIM/Features/Chat/ImageSendStage.swift
import Foundation

/// 图片消息阶段化重试的状态。设计 §6.3：
/// - `.notStarted` — 上传未开始 / 上传失败；retry 必须从 compress + upload 重新来
/// - `.uploaded(mediaURL:)` — 已上传成功但 `POST /api/messages` 失败；retry 跳过上传
///
/// 与 `LocalMessage.sendState` 是两个正交维度：sendState 描述 UI（pending/confirmed/failed），
/// imageSendStages 描述"下一次 retry 应该从哪一步开始"。
enum ImageSendStage: Sendable, Equatable {
    case notStarted
    case uploaded(mediaURL: String)
}
```

- [x] **Step 4: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ImageSendStageTests`
Expected: 3 个测试通过。

- [x] **Step 5: 给 ChatViewModel 加 imageSendStages + uploadRepo 依赖**

修改 `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`：

```swift
@Observable
@MainActor
final class ChatViewModel {
    // 在现有 messages / phase / isLoadingOlder ... 之后追加
    /// key 是 `LocalMessage.localId`（即 `clientTempId`）。confirmed 后 remove，避免长期堆积。
    private(set) var imageSendStages: [String: ImageSendStage] = [:]

    // 在现有 dependencies 区域，messageRepo 之后追加
    private let uploadRepo: UploadRepository?

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository? = nil,
        messageStore: MessageStore? = nil,
        metaStore: ConversationMetaStore? = nil,
        uploadRepo: UploadRepository? = nil,         // 新增；UI 层一定传，测试可以传 nil
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        // ... 现有 switch route 不变
        self.uploadRepo = uploadRepo
        // ... 其它赋值不变
    }
}
```

> `uploadRepo` 设默认值 `nil` 是为了让 P3/P4 已有的测试构造函数无需改动；只有 P5 新增的 ImageTests 才传具体的 mock。生产代码里 `ChatView.init` 一定会传，编译期由调用方保证非 nil（见 Task 11）。

- [x] **Step 6: 修 P3/P4 ChatView 的 init 调用（多了一个 uploadRepo 参数，默认 nil 不需要改，但保险起见 grep 一遍）**

```bash
grep -rn "ChatViewModel(\|ChatView(" ios-app/EchoIM ios-app/EchoIMTests
```

Step 6 的 grep 输出里：
- 测试里旧的 `ChatViewModel(...)` 都没传 `uploadRepo` → default nil，OK
- `ChatView.init(... )` 调用有几处，本任务先**不**给它加 uploadRepo 参数（Task 11 会改）

- [x] **Step 7: build 验证**

Run: `$BUILD`
Expected: SUCCEEDED。`uploadRepo: nil` 默认值让现有测试 / view 不需要改。

实现记录：本机可用模拟器是 `platform=iOS Simulator,OS=17.5,name=iPhone 15`；
`OS:latest` 会匹配到 iOS 26 SDK 但没有对应 iPhone 15 runtime。Task 5 的
`ImageSendStageTests` 与 build 均用 iOS 17.5 目的地通过。`ChatViewModel` 的旧构造调用
经 `rg "ChatViewModel\\(|ChatView\\(" ios-app/EchoIM ios-app/EchoIMTests` 确认仍走
`uploadRepo: nil` 默认值，本任务不改 UI 层注入。

- [x] **Step 8: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ImageSendStage.swift \
         ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
         ios-app/EchoIMTests/ImageSendStageTests.swift
git commit -m "feat(ios): add ImageSendStage and ChatViewModel uploadRepo slot"
```

---

## Task 6: ChatViewModel.sendImage — 上传 + 发送 happy path

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Create: `ios-app/EchoIMTests/ImageTestHelpers.swift`（共享给 Task 7 / 8 使用）
- Create: `ios-app/EchoIMTests/ChatViewModelImageTests.swift`

`sendImage(_ image: UIImage)` 流程（设计 §6.3）：

1. 压缩失败 → 静默 return（P5 范围内放弃 toast；P8 接日志框架时再补）
2. 生成 `tempId` + optimistic `LocalMessage`（`messageType: "image"`、`mediaUrl: nil`、`localImageData: 压缩后字节`、`sendState: .pending`）→ append；同时 `imageSendStages[tempId] = .notStarted`
3. 调 `uploadRepo.uploadMessageImage` → 成功后 `imageSendStages[tempId] = .uploaded(mediaURL)`
4. 调 `messageRepo.sendImage` → 成功后走现有 `mergeServerResult`（自动回填 conversationId / 替换 pending → confirmed / 写盘 / 保留 localImageData）；同时 `imageSendStages.removeValue(forKey: tempId)`
5. 上传或发送任意一步失败 → `markFailed(tempId:error:)`；`imageSendStages` 保持当前阶段，下次 retry 据此分叉

为测试可控，把第 1 步的"image → Data + dimensions"抽到 ViewModel 暴露的方法签名上：让 VM 直接收 `Data`（已经压缩好的字节流）。这样单测可以喂任意 Data 而无需构造 `UIImage`。UI 层（Task 11）负责 `UIImage → Data` 转换。

最终 ViewModel 暴露两个 public 入口和一个 internal 工作函数：

```swift
/// UI 层的入口：用户选图；负责压缩 → optimistic insert → 调 executeImageSend
func sendImage(_ image: UIImage) async

/// 单测的入口：跳过压缩，直接喂已经准备好的字节流；其余流程同 sendImage
func sendCompressedImage(data: Data, width: Int, height: Int) async

/// 内部工作函数：被 sendCompressedImage / retry 共享。
/// **关键**：retry 路径必须复用原 localId 直接调 executeImageSend，
/// **不能**调 sendCompressedImage——后者会重新生成 tempId、再插一条 optimistic bubble，
/// 把同一张失败的图变成两条记录。executeImageSend 内部按 imageSendStages[tempId] 分叉
/// 跳过已上传段（Task 7 实现）。
private func executeImageSend(tempId: String, data: Data, token: String, uploadRepo: UploadRepository) async
```

- [ ] **Step 1: 创建共享 mock helper（Task 7 / 8 都会复用）**

```swift
// ios-app/EchoIMTests/ImageTestHelpers.swift
import Foundation
@testable import EchoIM

/// 给 ChatViewModelImageTests / ChatViewModelWSTests 增量 / ChatViewModelCacheTests 增量共享。
/// 所有 mock 都是 file-scope public（同 target 内），让多个 @Suite 跨文件复用。

@MainActor
final class MockUploadRepo: UploadRepository {
    var uploadResult: String = "/uploads/messages/3-0.jpg"
    var uploadError: Error?
    private(set) var uploadCalls = 0

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        uploadCalls += 1
        if let uploadError { throw uploadError }
        return uploadResult
    }
}

@MainActor
final class SuspendableUploadRepo: UploadRepository {
    private var continuation: CheckedContinuation<String, Error>?

    func uploadMessageImage(data: Data, token: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    func resume(with mediaURL: String) {
        continuation?.resume(returning: mediaURL)
        continuation = nil
    }

    func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
final class MockMessageRepo: MessageRepository {
    struct SendImagePayload {
        let recipientId: Int
        let mediaUrl: String
        let clientTempId: String
    }

    var listResult: Result<[Message], Error> = .success([])
    var sendTextResult: Result<Message, Error> = .failure(NSError(domain: "unset", code: 0))
    var sendImageResult: Result<Message, Error> = .failure(NSError(domain: "unset", code: 0))
    var markReadResult: Result<Void, Error> = .success(())

    private(set) var sendImageCalls = 0
    private(set) var sendImagePayloads: [SendImagePayload] = []

    func list(conversationId: Int, cursor: MessageCursor?, limit: Int?, token: String) async throws -> [Message] {
        try listResult.get()
    }

    func sendText(recipientId: Int, body: String, clientTempId: String, token: String) async throws -> Message {
        try sendTextResult.get()
    }

    func sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message {
        sendImageCalls += 1
        sendImagePayloads.append(.init(recipientId: recipientId, mediaUrl: mediaUrl, clientTempId: clientTempId))
        return try sendImageResult.get()
    }

    func markRead(conversationId: Int, lastReadMessageId: Int, token: String) async throws {
        try markReadResult.get()
    }
}

/// 共享的 ChatViewModel 构造帮手。Task 6 / 7 都用；Task 8 自己再写一份带 store 的版本（见 Task 8）。
@MainActor
func makeImageVM(
    currentUserId: Int,
    peerId: Int,
    conversationId: Int?,
    upload: UploadRepository,
    messages: MessageRepository,
    messageStore: MessageStore? = nil,
    metaStore: ConversationMetaStore? = nil
) -> ChatViewModel {
    let peer = UserProfile(id: peerId, username: "p", displayName: nil, avatarUrl: nil)
    let route: ChatRoute = conversationId.map { id in
        ChatRoute.conversation(
            Conversation(
                id: id, createdAt: Date(), peer: peer,
                lastMessageBody: nil, lastMessageType: nil, lastMessageSenderId: nil,
                lastMessageAt: nil, lastReadMessageId: nil, unreadCount: 0
            )
        )
    } ?? .peer(peer)

    return ChatViewModel(
        route: route,
        currentUserId: currentUserId,
        messageRepo: messages,
        wsClient: nil,
        conversationRepository: nil,
        messageStore: messageStore,
        metaStore: metaStore,
        uploadRepo: upload,
        tokenProvider: { "tok" }
    )
}
```

- [ ] **Step 2: 写测试 — 完整 happy path（compress + upload + send 都成功）**

```swift
// ios-app/EchoIMTests/ChatViewModelImageTests.swift
import Testing
import Foundation
@testable import EchoIM

@MainActor
@Suite("ChatViewModel — Image send")
struct ChatViewModelImageTests {
    @Test
    func sendImageHappyPathInsertsPendingThenConfirms() async throws {
        let upload = MockUploadRepo()
        upload.uploadResult = "/uploads/messages/3-1745800000000.jpg"

        let messages = MockMessageRepo()
        messages.sendImageResult = .success(
            Message(
                id: 200,
                conversationId: 5,
                senderId: 3,
                body: nil,
                messageType: "image",
                mediaUrl: "/uploads/messages/3-1745800000000.jpg",
                createdAt: Date(),
                clientTempId: nil
            )
        )

        let vm = makeImageVM(currentUserId: 3, peerId: 9, conversationId: 5,
                             upload: upload, messages: messages)

        let imgData = Data(repeating: 0xFF, count: 16)
        await vm.sendCompressedImage(data: imgData, width: 100, height: 100)

        // 上传与发送各调用一次
        #expect(upload.uploadCalls == 1)
        #expect(messages.sendImageCalls == 1)
        #expect(messages.sendImagePayloads.first?.mediaUrl == "/uploads/messages/3-1745800000000.jpg")

        // bubble 已 confirmed；localImageData 保留
        #expect(vm.messages.count == 1)
        let local = try #require(vm.messages.first)
        #expect(local.sendState == .confirmed)
        #expect(local.message.id == 200)
        #expect(local.message.messageType == "image")
        #expect(local.localImageData == imgData)

        // 阶段表清空
        #expect(vm.imageSendStages.isEmpty)
    }

    @Test
    func sendImageInsertsOptimisticBubbleBeforeUpload() async throws {
        // 这个测试验证 optimistic insert 时机：upload 还没返回，bubble 应该已经在 messages 里
        let upload = SuspendableUploadRepo()
        let messages = MockMessageRepo()

        let vm = makeImageVM(currentUserId: 3, peerId: 9, conversationId: 5,
                             upload: upload, messages: messages)

        Task {
            await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)
        }

        // 让 vm.send 跑到 upload 那一行；await Task.yield() 一次足以触发 optimistic insert
        await Task.yield()
        await Task.yield()

        #expect(vm.messages.count == 1)
        let local = try #require(vm.messages.first)
        #expect(local.sendState == .pending)
        #expect(local.message.messageType == "image")
        #expect(local.message.mediaUrl == nil)        // 还没拿到 media_url
        #expect(local.localImageData == Data([0xFF, 0xD8]))

        upload.resume(with: "/uploads/messages/3-1745800000000.jpg")
    }
}
```

- [ ] **Step 3: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelImageTests`
Expected: 编译失败（`sendCompressedImage` 未定义；helper 文件 OK 但 VM 里没方法可调）。

- [ ] **Step 4: 实现 sendImage / sendCompressedImage**

在 `ChatViewModel.swift` 的 `sendText` 之后插入：

```swift
func sendImage(_ image: UIImage) async {
    guard let compressed = ImageCompressor.compressForUpload(image) else {
        // 编码失败极少发生；P5 先静默放弃，P8 接日志/提示体系时再补用户反馈。
        return
    }
    await sendCompressedImage(data: compressed.data, width: compressed.width, height: compressed.height)
}

func sendCompressedImage(data: Data, width: Int, height: Int) async {
    guard let token = tokenProvider() else { return }
    guard let uploadRepo else { return }

    let tempId = makeTempId()
    let optimistic = Message(
        id: -Int.random(in: 1...Int.max),
        conversationId: conversationId ?? -1,
        senderId: currentUserId,
        body: nil,
        messageType: "image",
        mediaUrl: nil,
        createdAt: Date(),
        clientTempId: tempId
    )
    messages.append(
        LocalMessage(
            localId: tempId,
            message: optimistic,
            sendState: .pending,
            localImageData: data
        )
    )
    imageSendStages[tempId] = .notStarted

    await executeImageSend(tempId: tempId, data: data, token: token, uploadRepo: uploadRepo)
}

private func executeImageSend(
    tempId: String,
    data: Data,
    token: String,
    uploadRepo: UploadRepository
) async {
    // Stage 1: upload；如果当前 stage 已经是 .uploaded（来自 retry），跳过
    let mediaURL: String
    if case .uploaded(let cached) = imageSendStages[tempId] {
        mediaURL = cached
    } else {
        do {
            mediaURL = try await uploadRepo.uploadMessageImage(data: data, token: token)
            imageSendStages[tempId] = .uploaded(mediaURL: mediaURL)
        } catch {
            markFailed(tempId: tempId, error: error)
            return
        }
    }

    // Stage 2: send message
    do {
        let result = try await messageRepo.sendImage(
            recipientId: peer.id,
            mediaUrl: mediaURL,
            clientTempId: tempId,
            token: token
        )
        mergeServerResult(result, tempId: tempId)
        imageSendStages.removeValue(forKey: tempId)
    } catch {
        markFailed(tempId: tempId, error: error)
    }
}
```

> 注意 `import UIKit`：如果文件目前只 `import Foundation`，加一行 `import UIKit`。否则 `UIImage` 类型不可见。

- [ ] **Step 5: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelImageTests`
Expected: 2 个测试通过。

- [ ] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
         ios-app/EchoIMTests/ImageTestHelpers.swift \
         ios-app/EchoIMTests/ChatViewModelImageTests.swift
git commit -m "feat(ios): ChatViewModel sendImage with optimistic bubble"
```

---

## Task 7: 上传失败 / 发送失败两条分叉 + 阶段化重试

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
- Modify: `ios-app/EchoIMTests/ChatViewModelImageTests.swift`

设计依据：§6.3 阶段化重试。

- [ ] **Step 1: 写四个失败 / 重试测试**

在 `ChatViewModelImageTests` 里追加：

```swift
@Test
func sendImageMarksFailedWhenUploadFails() async throws {
    let upload = MockUploadRepo()
    upload.uploadError = APIError.network(URLError(.notConnectedToInternet))
    let messages = MockMessageRepo()

    let vm = makeImageVM(currentUserId: 3, peerId: 9, conversationId: 5,
                    upload: upload, messages: messages)

    await vm.sendCompressedImage(data: Data([0xFF]), width: 10, height: 10)

    #expect(vm.messages.count == 1)
    let local = try #require(vm.messages.first)
    if case .failed = local.sendState {
        // expected
    } else {
        Issue.record("expected .failed, got \(local.sendState)")
    }
    // 上传失败 → 阶段保持 .notStarted；retry 必须从头来
    #expect(vm.imageSendStages[local.localId] == .notStarted)
    // sendImage 不应被调用
    #expect(messages.sendImageCalls == 0)
}

@Test
func sendImageMarksFailedWhenSendFailsButKeepsUploadedStage() async throws {
    let upload = MockUploadRepo()
    upload.uploadResult = "/uploads/messages/3-1745800000000.jpg"
    let messages = MockMessageRepo()
    messages.sendImageResult = .failure(APIError.network(URLError(.timedOut)))

    let vm = makeImageVM(currentUserId: 3, peerId: 9, conversationId: 5,
                    upload: upload, messages: messages)

    await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)

    let local = try #require(vm.messages.first)
    if case .failed = local.sendState {
        // expected
    } else {
        Issue.record("expected .failed")
    }
    // 上传成功了 → 阶段必须是 .uploaded；retry 不应再上传
    #expect(vm.imageSendStages[local.localId] == .uploaded(mediaURL: "/uploads/messages/3-1745800000000.jpg"))
    #expect(upload.uploadCalls == 1)
    #expect(messages.sendImageCalls == 1)
}

@Test
func retrySkipsUploadWhenStageIsUploaded() async throws {
    let upload = MockUploadRepo()
    upload.uploadResult = "/uploads/messages/3-1745800000000.jpg"

    let messages = MockMessageRepo()
    // 先让 sendImage 第一次失败
    messages.sendImageResult = .failure(APIError.network(URLError(.timedOut)))

    let vm = makeImageVM(currentUserId: 3, peerId: 9, conversationId: 5,
                    upload: upload, messages: messages)
    await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)

    let localId = try #require(vm.messages.first?.localId)

    // 重试前：让 sendImage 这次成功
    messages.sendImageResult = .success(
        Message(
            id: 300,
            conversationId: 5,
            senderId: 3,
            body: nil,
            messageType: "image",
            mediaUrl: "/uploads/messages/3-1745800000000.jpg",
            createdAt: Date(),
            clientTempId: nil
        )
    )

    await vm.retry(localId: localId)

    // upload 不应被调用第二次（关键断言）
    #expect(upload.uploadCalls == 1, "retry 命中 .uploaded 阶段时不应重新上传")
    #expect(messages.sendImageCalls == 2)

    let updated = try #require(vm.messages.first)
    #expect(updated.sendState == .confirmed)
    #expect(updated.message.id == 300)
    #expect(vm.imageSendStages.isEmpty)
}

@Test
func retryRestartsFromUploadWhenStageIsNotStarted() async throws {
    let upload = MockUploadRepo()
    upload.uploadError = APIError.network(URLError(.timedOut))

    let messages = MockMessageRepo()

    let vm = makeImageVM(currentUserId: 3, peerId: 9, conversationId: 5,
                    upload: upload, messages: messages)
    await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)

    let localId = try #require(vm.messages.first?.localId)

    // 重试前：让 upload 这次成功
    upload.uploadError = nil
    upload.uploadResult = "/uploads/messages/3-1745800000001.jpg"
    messages.sendImageResult = .success(
        Message(
            id: 301,
            conversationId: 5,
            senderId: 3,
            body: nil,
            messageType: "image",
            mediaUrl: "/uploads/messages/3-1745800000001.jpg",
            createdAt: Date(),
            clientTempId: nil
        )
    )

    await vm.retry(localId: localId)

    #expect(upload.uploadCalls == 2, "上传失败后 retry 必须重新走上传")
    #expect(messages.sendImageCalls == 1)
    let updated = try #require(vm.messages.first)
    #expect(updated.sendState == .confirmed)
    #expect(updated.message.mediaUrl == "/uploads/messages/3-1745800000001.jpg")
}

@Test
func retryNoOpsWhenLocalImageDataMissing() async throws {
    // 边界：失败的 image bubble，但 localImageData 是 nil（VM 重建后理论不会进 P5；
    // 这里防御性测试，确保 retry 安全 no-op 而不是 crash）
    let upload = MockUploadRepo()
    let messages = MockMessageRepo()
    let vm = makeImageVM(currentUserId: 3, peerId: 9, conversationId: 5,
                    upload: upload, messages: messages)

    let tempId = "manual-tmp"
    vm._injectFailedImageBubbleForTesting(
        tempId: tempId,
        message: Message(
            id: -1, conversationId: 5, senderId: 3, body: nil,
            messageType: "image", mediaUrl: nil, createdAt: Date(), clientTempId: tempId
        ),
        stage: .notStarted,
        localData: nil
    )

    await vm.retry(localId: tempId)

    #expect(upload.uploadCalls == 0)
    #expect(messages.sendImageCalls == 0)
    let local = try #require(vm.messages.first)
    if case .failed = local.sendState {
        // unchanged
    } else {
        Issue.record("expected .failed unchanged")
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelImageTests`
Expected: 4 个新测试编译失败 / 行为错（`retry` 还在走文字路径；测试入口 `_injectFailedImageBubbleForTesting` 未定义）。

- [ ] **Step 3: 改造 `retry(localId:)` 按 messageType 分叉**

把现有 `func retry(localId:)` 替换为：

```swift
func retry(localId: String) async {
    guard let index = messages.firstIndex(where: { $0.localId == localId }) else { return }
    guard case .failed = messages[index].sendState else { return }
    let local = messages[index]

    if local.message.messageType == "image" {
        guard let token = tokenProvider() else { return }
        guard let uploadRepo else { return }
        // VM 重建后会丢 localImageData（已知妥协）；此时直接 no-op，等待用户重选图。
        guard let data = local.localImageData else { return }

        messages[index].sendState = .pending
        await executeImageSend(tempId: localId, data: data, token: token, uploadRepo: uploadRepo)
        return
    }

    // 文字 retry 路径保持不变
    guard let body = local.message.body else { return }
    guard let token = tokenProvider() else { return }
    messages[index].sendState = .pending
    await performSend(body: body, tempId: localId, token: token)
}
```

`executeImageSend` 的开头已经有 `if case .uploaded(let cached) = imageSendStages[tempId] { ... } else { upload }` 分叉（Task 6 实现），所以阶段化重试自动生效——无需在 `retry` 里再判断。

- [ ] **Step 4: 加一个 `internal` 测试入口 — 注入 failed image bubble**

在 `ChatViewModel.swift` 文件末尾追加（用 `#if DEBUG` 圈起来，避免污染 release）：

```swift
#if DEBUG
extension ChatViewModel {
    /// 仅 P5 ChatViewModelImageTests 用：手工注入一个 failed image bubble 与 stage，
    /// 用来覆盖 "retry on bubble whose localImageData was lost" 边界。
    func _injectFailedImageBubbleForTesting(
        tempId: String,
        message: Message,
        stage: ImageSendStage,
        localData: Data?
    ) {
        messages.append(
            LocalMessage(
                localId: tempId,
                message: message,
                sendState: .failed("injected"),
                localImageData: localData
            )
        )
        imageSendStages[tempId] = stage
    }
}
#endif
```

> 用 `_` 前缀强调它是私有约定（Swift 没有 `@testable internal-private` 区分）。

- [ ] **Step 5: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelImageTests`
Expected: 6 个测试全部通过（Task 6 的 2 个 + 本任务的 4 个）。

- [ ] **Step 6: 跑全套，确保 P3/P4 文字 retry 不退化**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelSendTests EchoIMTests/ChatViewModelCacheTests`
Expected: 全过。

- [ ] **Step 7: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ChatViewModel.swift \
         ios-app/EchoIMTests/ChatViewModelImageTests.swift
git commit -m "feat(ios): branch retry by messageType, image skip-upload path"
```

---

## Task 8: WS 路径 / SwiftData 写盘对图片消息的覆盖性测试

**Files:**
- Modify: `ios-app/EchoIMTests/ChatViewModelWSTests.swift`（已存在）
- Modify: `ios-app/EchoIMTests/ChatViewModelCacheTests.swift`（已存在）

P4 的 `handleIncomingMessage` / `writeThroughAndMeta` 与 P3 的 `mergeServerResult` 已经按 `Message.mediaUrl` 透传字段，理论上对 image 类型免改。本任务**不改实现**，只补两个回归测试，明确"WS 推一条 image / 自己发的 image 都正确落盘并保留 localImageData"。

- [ ] **Step 1: 在 `ChatViewModelWSTests` 增加 image 回归测试**

> 现有 `ChatViewModelWSTests` 是 nested `FakeMessageRepo` + 直接 `ChatViewModel(...)` 构造（`ChatViewModelWSTests.swift:8`）。新增测试**不**用 `FakeMessageRepo`——直接用 Task 6 共享的 `MockUploadRepo` / `MockMessageRepo` + `makeImageVM`。`handleWSEvent` 是 internal，测试无需 `attachWSSubscription` 这一层就能直接喂事件。

```swift
// 加到 ChatViewModelWSTests struct 末尾（与现有 @Test 同级）：

@Test
func wsImageMessageFromPeerAppendsAsImageBubble() async throws {
    let upload = MockUploadRepo()
    let messages = MockMessageRepo()
    let vm = makeImageVM(
        currentUserId: 3, peerId: 9, conversationId: 5,
        upload: upload, messages: messages
    )

    vm.handleWSEvent(.messageNew(
        Message(
            id: 500,
            conversationId: 5,
            senderId: 9,
            body: nil,
            messageType: "image",
            mediaUrl: "/uploads/messages/9-1745900000000.jpg",
            createdAt: Date(),
            clientTempId: nil
        )
    ))

    // 让 write-through fire-and-forget Task 跑完
    await Task.yield()
    await Task.yield()

    let last = try #require(vm.messages.last)
    #expect(last.message.messageType == "image")
    #expect(last.message.mediaUrl == "/uploads/messages/9-1745900000000.jpg")
    #expect(last.localImageData == nil, "对方的图片不带本地 Data，UI 走 Nuke 远程加载")
    #expect(last.sendState == .confirmed)
}

@Test
func wsEchoFromSelfMergesIntoPendingImageBubblePreservingLocalData() async throws {
    let upload = MockUploadRepo()
    upload.uploadResult = "/uploads/messages/3-1.jpg"
    let messages = MockMessageRepo()
    messages.sendImageResult = .success(
        Message(
            id: 600, conversationId: 5, senderId: 3,
            body: nil, messageType: "image",
            mediaUrl: "/uploads/messages/3-1.jpg",
            createdAt: Date(), clientTempId: "tmp-x"
        )
    )

    let vm = makeImageVM(
        currentUserId: 3, peerId: 9, conversationId: 5,
        upload: upload, messages: messages
    )

    let imgBytes = Data([0xFF, 0xD8, 0xFF])
    await vm.sendCompressedImage(data: imgBytes, width: 10, height: 10)

    // mergeServerResult 已经在 sendCompressedImage 里跑过；这里再喂一次 WS echo（同 client_temp_id），
    // 应当幂等：不重复 append、保留 localImageData
    let echo = Message(
        id: 600, conversationId: 5, senderId: 3,
        body: nil, messageType: "image",
        mediaUrl: "/uploads/messages/3-1.jpg",
        createdAt: Date(), clientTempId: try #require(vm.messages.first?.localId)
    )
    vm.handleWSEvent(.messageNew(echo))
    await Task.yield()

    #expect(vm.messages.count == 1)
    #expect(vm.messages[0].localImageData == imgBytes, "WS echo 不应擦掉 localImageData")
    #expect(vm.messages[0].sendState == .confirmed)
}
```

- [ ] **Step 2: 在 `ChatViewModelCacheTests` 增加 image 写盘回归**

> `ChatViewModelCacheTests` 现有用 `try makeContainer()` + `MessageStore(modelContainer: container)` + `ConversationMetaStore(modelContainer: container)` 构造 store（`ChatViewModelCacheTests.swift:48`）。新增测试沿用同一模式，store 即用即弃。**不**自行发明 `freshMessageStore()` / `freshMetaStore()` helper。

```swift
// 加到 ChatViewModelCacheTests struct 末尾（与现有 @Test 同级）：

@MainActor
@Test
func confirmedImageMessageWritesThroughToCache() async throws {
    let container = try makeContainer()
    let messageStore = MessageStore(modelContainer: container)
    let metaStore = ConversationMetaStore(modelContainer: container)

    let upload = MockUploadRepo()
    upload.uploadResult = "/uploads/messages/3-2.jpg"
    let messages = MockMessageRepo()
    messages.sendImageResult = .success(
        Message(
            id: 700, conversationId: 5, senderId: 3,
            body: nil, messageType: "image",
            mediaUrl: "/uploads/messages/3-2.jpg",
            createdAt: Date(), clientTempId: nil
        )
    )

    let vm = makeImageVM(
        currentUserId: 3, peerId: 9, conversationId: 5,
        upload: upload, messages: messages,
        messageStore: messageStore, metaStore: metaStore
    )

    await vm.sendCompressedImage(data: Data([0xFF]), width: 10, height: 10)
    // 让 fire-and-forget Task 跑完
    await Task.yield()
    await Task.yield()
    await Task.yield()

    let cached = try await messageStore.loadLatest(conversationId: 5, limit: 10)
    #expect(cached.contains { $0.id == 700 && $0.mediaUrl == "/uploads/messages/3-2.jpg" })

    let meta = try #require(try await metaStore.load(conversationId: 5))
    #expect(meta.lastMessageType == "image")
    #expect(meta.newestCachedMessageId == 700)
}

@MainActor
@Test
func pendingImageBubbleIsNotWrittenToCache() async throws {
    let container = try makeContainer()
    let messageStore = MessageStore(modelContainer: container)
    let metaStore = ConversationMetaStore(modelContainer: container)

    let upload = SuspendableUploadRepo()
    let messages = MockMessageRepo()

    let vm = makeImageVM(
        currentUserId: 3, peerId: 9, conversationId: 5,
        upload: upload, messages: messages,
        messageStore: messageStore, metaStore: metaStore
    )

    Task {
        await vm.sendCompressedImage(data: Data([0xFF, 0xD8]), width: 10, height: 10)
    }
    // pending 阶段应当不写盘
    await Task.yield()
    await Task.yield()

    let cached = try await messageStore.loadLatest(conversationId: 5, limit: 10)
    #expect(cached.isEmpty, "pending image 不应进入 SwiftData（id 是负数 + media_url nil 会破坏不变式）")

    upload.resume(with: "/uploads/messages/3-3.jpg")  // 解锁，避免 task 长跑
}
```

- [ ] **Step 3: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ChatViewModelWSTests EchoIMTests/ChatViewModelCacheTests`
Expected: 全过；新增 4 个测试也通过，无需改实现。

> 如果 `pendingImageBubbleIsNotWrittenToCache` 失败，说明 `sendCompressedImage` 在 optimistic insert 时调用了 `writeThroughAndMeta`——回到 Task 6 检查实现：optimistic insert 路径**不**应触发 write-through，只有 `mergeServerResult`（confirmed）和 `handleIncomingMessage`（confirmed）才写盘。

- [ ] **Step 4: 提交**

```bash
git add ios-app/EchoIMTests/ChatViewModelWSTests.swift \
         ios-app/EchoIMTests/ChatViewModelCacheTests.swift
git commit -m "test(ios): regression coverage for image WS echo and cache write-through"
```

---

## Task 9: ImageMessageBubble 与 MessageBubble 派发

**Files:**
- Create: `ios-app/EchoIM/Features/Chat/ImageMessageBubble.swift`
- Modify: `ios-app/EchoIM/Features/Chat/MessageBubble.swift`

设计依据：§6.4 + §6.5。优先用 `localImageData`（Data → UIImage 直接渲染），否则走 `LazyImage(url:)` Nuke 远程加载，4:3 占位避免抖动。

- [ ] **Step 1: 创建 ImageMessageBubble**

```swift
// ios-app/EchoIM/Features/Chat/ImageMessageBubble.swift
import NukeUI
import SwiftUI

struct ImageMessageBubble: View {
    let message: LocalMessage
    let isSelf: Bool
    var onTap: () -> Void = {}
    var onRetry: () -> Void = {}

    var body: some View {
        HStack {
            if isSelf { Spacer(minLength: 40) }

            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                imageContent
                    .frame(maxWidth: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .center) {
                        if message.sendState == .pending {
                            // pending 期间在缩略图上覆盖一层半透明 + spinner
                            ZStack {
                                Color.black.opacity(0.25)
                                ProgressView().tint(.white)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .onTapGesture {
                        if case .pending = message.sendState { return }
                        onTap()
                    }

                footer
            }

            if !isSelf { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        // localImageData 优先：避免发送后立刻切换到远端 URL 触发 Nuke 重新加载（设计 §6.4）
        if let data = message.localImageData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
        } else if let url = remoteURL {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else if state.error != nil {
                    placeholder { Image(systemName: "photo.badge.exclamationmark") }
                } else {
                    placeholder { ProgressView() }
                }
            }
        } else {
            placeholder { Image(systemName: "photo") }
        }
    }

    private var remoteURL: URL? {
        // 服务端回的 mediaUrl 是相对路径；统一用 Endpoints.absolute 拼出绝对 URL。
        Endpoints.absolute(message.message.mediaUrl)
    }

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // 设计 §6.5：服务端 Message 不带 width/height，4:3 是常见手机照片比例，
        // 加载完后 Image(uiImage:) 自适应真实比例，会有一次重排，可接受。
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            content()
                .foregroundStyle(.secondary)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
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
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("发送失败")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("重试", action: onRetry)
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
}
```

- [ ] **Step 2: 改 MessageBubble 派发到 image / text**

```swift
// ios-app/EchoIM/Features/Chat/MessageBubble.swift
import SwiftUI

struct MessageBubble: View {
    let message: LocalMessage
    let isSelf: Bool
    var onRetry: () -> Void = {}
    var onOpenImage: () -> Void = {}     // 新增：图片点击进 Lightbox

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

    private var textBubble: some View {
        // 把原 body 的 HStack/VStack/bubble/footer 实现挪进来；现有逻辑保持不变
        HStack {
            if isSelf {
                Spacer(minLength: 40)
            }

            VStack(alignment: isSelf ? .trailing : .leading, spacing: 4) {
                Text(message.message.body ?? "")
                    .font(.body)
                    .foregroundStyle(isSelf ? .white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelf ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                    )
                    .opacity(message.sendState == .pending ? 0.65 : 1.0)
                footer
            }

            if !isSelf {
                Spacer(minLength: 40)
            }
        }
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
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("发送失败")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Button("重试", action: onRetry)
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
}
```

- [ ] **Step 3: build 验证**

Run: `$BUILD`
Expected: SUCCEEDED；ChatView 调用 `MessageBubble(message:isSelf:onRetry:)` 现有签名仍然兼容（onOpenImage 默认 `{}`）。

- [ ] **Step 4: 提交**

```bash
git add ios-app/EchoIM/Features/Chat/ImageMessageBubble.swift \
         ios-app/EchoIM/Features/Chat/MessageBubble.swift
git commit -m "feat(ios): split MessageBubble into text/image variants"
```

---

## Task 10: Lightbox（全屏 pinch/zoom 预览）

**Files:**
- Create: `ios-app/EchoIM/Core/UI/ZoomableImageView.swift`
- Create: `ios-app/EchoIM/Features/Chat/Lightbox.swift`

SwiftUI 没有内建 pinch/zoom + double-tap-to-zoom；用 `UIScrollView` 包一层。`Lightbox` 是 SwiftUI sheet / fullScreenCover 入口，封装"加载图片 → 居中 → 关闭按钮 → 滑下关闭"。

- [ ] **Step 1: 创建 ZoomableImageView**

```swift
// ios-app/EchoIM/Core/UI/ZoomableImageView.swift
import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.imageView = imageView

        scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // image 变了就替换；当前 Lightbox 一次只展一张，updateUIView 多由布局触发，无需特别处理
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scroll = recognizer.view as? UIScrollView else { return }
            if scroll.zoomScale > scroll.minimumZoomScale {
                scroll.setZoomScale(scroll.minimumZoomScale, animated: true)
            } else {
                let location = recognizer.location(in: imageView)
                let zoomRect = CGRect(
                    x: location.x - 50, y: location.y - 50,
                    width: 100, height: 100
                )
                scroll.zoom(to: zoomRect, animated: true)
            }
        }
    }
}
```

- [ ] **Step 2: 创建 Lightbox sheet**

```swift
// ios-app/EchoIM/Features/Chat/Lightbox.swift
import Nuke           // ImagePipeline / ImageRequest 在 Nuke，不在 NukeUI
import NukeUI
import SwiftUI
import UIKit

struct Lightbox: View {
    /// 优先用本地 Data（发送方），否则下载远端 URL（接收方）
    let localData: Data?
    let remoteURL: URL?
    let onClose: () -> Void

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = loadedImage {
                ZoomableImageView(image: image)
                    .ignoresSafeArea()
            } else if remoteURL != nil {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
                    .font(.largeTitle)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("lightboxClose")
                    .padding()
                }
                Spacer()
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        if let data = localData, let ui = UIImage(data: data) {
            loadedImage = ui
            return
        }

        guard let remoteURL else { return }

        // 走 Nuke 拿磁盘缓存命中或下载；与 Bubble 上的 LazyImage 共用 ImagePipeline，
        // 多数情况下是直接命中。
        let pipeline = ImagePipeline.shared
        let request = ImageRequest(url: remoteURL)
        do {
            let response = try await pipeline.image(for: request)
            loadedImage = response
        } catch {
            // 留空显示"图片不可用"占位；用户可滑下关闭
        }
    }
}
```

> `ImagePipeline.shared.image(for:)` 是 Nuke 12+ 的 async API；如果项目锁的版本低于 12，回退到完成回调包装：
>
> ```swift
> let response = try await withCheckedThrowingContinuation { cont in
>     pipeline.loadImage(with: request, completion: { result in
>         cont.resume(with: result.map(\.image))
>     })
> }
> ```
>
> 检查命令：`grep -A2 "Nuke" ios-app/EchoIM.xcodeproj/project.pbxproj | grep version`

- [ ] **Step 3: build 验证**

Run: `$BUILD`
Expected: SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add ios-app/EchoIM/Core/UI/ZoomableImageView.swift \
         ios-app/EchoIM/Features/Chat/Lightbox.swift
git commit -m "feat(ios): add Lightbox with pinch/zoom"
```

---

## Task 11: ChatView 接 PhotosPicker + Lightbox + 注入 UploadRepository

**Files:**
- Modify: `ios-app/EchoIM/Features/Chat/ChatView.swift`
- Modify: `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`（destination 注入新参数）
- Modify: `ios-app/EchoIM/Features/Contacts/ContactsView.swift`（同上，从联系人点开聊天的入口）
- Modify: `ios-app/EchoIM/Features/Main/MainTabView.swift`（构造 ChatView 多了一处地方注入）
- Modify: `ios-app/EchoIM/App/UserSession.swift`（新工厂方法）

UI 集成的核心是 `PhotosPicker`：iOS 17+ 直接 `loadTransferable(type: Data.self)`，避免传统 `PHAsset` 路径。

- [ ] **Step 1: 给 UserSession 加 makeUploadRepository**

修改 `ios-app/EchoIM/App/UserSession.swift`，在 `makeMessageRepository()` 之后追加：

```swift
func makeUploadRepository() -> UploadRepository {
    UploadRepositoryImpl(api: apiClient)
}
```

- [ ] **Step 2: 修改 ChatView.init 接收 uploadRepo + 传给 VM + 加 PhotosPicker / Lightbox**

```swift
// ios-app/EchoIM/Features/Chat/ChatView.swift
import PhotosUI
import SwiftUI

struct ChatView: View {
    @State private var vm: ChatViewModel
    @State private var draft = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var lightboxBubble: LocalMessage?

    init(
        route: ChatRoute,
        currentUserId: Int,
        messageRepo: MessageRepository,
        messageStore: MessageStore?,
        metaStore: ConversationMetaStore?,
        wsClient: WebSocketClient?,
        conversationRepository: ConversationRepository?,
        uploadRepo: UploadRepository,                 // 新增；非 optional
        tokenProvider: @escaping @MainActor () -> String?
    ) {
        _vm = State(
            wrappedValue: ChatViewModel(
                route: route,
                currentUserId: currentUserId,
                messageRepo: messageRepo,
                wsClient: wsClient,
                conversationRepository: conversationRepository,
                messageStore: messageStore,
                metaStore: metaStore,
                uploadRepo: uploadRepo,
                tokenProvider: tokenProvider
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
        .navigationTitle(vm.peer.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.attachWSSubscription()
            await vm.load()
        }
        .onDisappear {
            vm.detachWSSubscription()
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handlePickedItem(newItem)
                pickedItem = nil
            }
        }
        .fullScreenCover(item: $lightboxBubble) { bubble in
            Lightbox(
                localData: bubble.localImageData,
                remoteURL: Endpoints.absolute(bubble.message.mediaUrl),
                onClose: { lightboxBubble = nil }
            )
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if vm.hasMoreOlder {
                        Button {
                            Task { await vm.loadOlder() }
                        } label: {
                            if vm.isLoadingOlder { ProgressView() } else { Text("加载更早消息").font(.caption) }
                        }
                        .buttonStyle(.borderless)
                        .padding(.vertical, 6)
                    }

                    ForEach(vm.messages) { message in
                        MessageBubble(
                            message: message,
                            isSelf: message.message.senderId == vm.currentUserId,
                            onRetry: { Task { await vm.retry(localId: message.localId) } },
                            onOpenImage: { lightboxBubble = message }
                        )
                        .id(message.localId)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(uiColor: .systemBackground))
            .overlay {
                if vm.phase == .loading, vm.messages.isEmpty {
                    ProgressView()
                }
            }
            .onChange(of: vm.messages.last?.localId) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .regular))
            }
            .accessibilityLabel("发送图片")
            .accessibilityIdentifier("chatImagePicker")

            TextField("说点什么...", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.send)
                .accessibilityIdentifier("chatInput")

            Button {
                let text = draft
                draft = ""
                Task { await vm.sendText(text) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSend)
            .accessibilityLabel("发送")
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            // 不弹 toast；P5 范围内静默放弃。P8 可接日志框架。
            return
        }
        await vm.sendImage(image)
    }
}
```

- [ ] **Step 3: 让 LocalMessage 满足 `Identifiable`（已经满足；`fullScreenCover(item:)` 需要它）**

`LocalMessage` 已经 `Identifiable`（`var id: String { localId }`），无需改。

- [ ] **Step 4: 修改三个调用 ChatView.init 的地方传 uploadRepo**

```bash
grep -rn "ChatView(\s*$\|ChatView(" ios-app/EchoIM/Features
```

应能匹配三处：
- `Features/Conversations/ConversationsListView.swift:141` — destination
- `Features/Contacts/ContactsView.swift` — 联系人点击进聊天页
- 可能还有一处入口（草稿 / push notification 入口）

每处都改成：

```swift
ChatView(
    route: route,
    currentUserId: currentUserId,
    messageRepo: messageRepo,
    messageStore: messageStore,
    metaStore: metaStore,
    wsClient: wsClient,
    conversationRepository: conversationRepo,
    uploadRepo: uploadRepo,                      // 新增
    tokenProvider: tokenProvider
)
```

并把 `ConversationsListView` / `ContactsView` 的 init 增加一个 `uploadRepo: UploadRepository` 参数（非 optional），由 `MainTabView` 在 chatsTab / contactsTab 注入：

```swift
// MainTabView.swift chatsTab
ConversationsListView(
    repository: session.makeConversationRepository(),
    messageRepo: session.makeMessageRepository(),
    metaStore: session.conversationMetaStore(),
    messageStore: session.messageStore(),
    wsClient: session.wsClient,
    uploadRepo: session.makeUploadRepository(),  // 新增
    currentUserId: container.currentUser?.id ?? 0,
    tokenProvider: { [tokenStore = container.tokenStore] in
        (try? tokenStore.load())?.token
    }
)
```

`ContactsView` 同理增加 `uploadRepo` 参数 + 内部传递到 ChatView。

- [ ] **Step 5: build + 全套测试验证**

Run: `$BUILD && $TEST`
Expected: 全过。如果旧 ChatViewModelImageTests / Send / Cache / WS / Load tests 因为 ChatView init 签名变了编译失败，回去补 mock 调用方的参数（应该不会，VM 测试不直接构造 ChatView）。

- [ ] **Step 6: 模拟器手工冒烟**

启动模拟器，登录两个账号，互发图片：
- 选图 → 缩略图立刻出现（pending overlay）
- 服务端返回后 overlay 消失
- 点缩略图进 Lightbox，pinch zoom + double-tap 工作
- 断网下选图 → 失败 → bubble 显示重试 → 联网点重试 → 成功

> 真机/模拟器手工：先在 `~/Library/Developer/CoreSimulator/...` 装两个用户，或者用 `multi` profile 起两个 server 实例 + 两个模拟器。

- [ ] **Step 7: 提交**

```bash
git add ios-app/EchoIM/App/UserSession.swift \
         ios-app/EchoIM/Features/Chat/ChatView.swift \
         ios-app/EchoIM/Features/Conversations/ConversationsListView.swift \
         ios-app/EchoIM/Features/Contacts/ContactsView.swift \
         ios-app/EchoIM/Features/Main/MainTabView.swift
git commit -m "feat(ios): wire PhotosPicker and Lightbox into ChatView"
```

---

## Task 12: ChatsList 图片预览 / 增量验证

**Files:**
- Test: 验证现有行为，无源码改动；如果发现回归，再补到 `ConversationsListViewModelTests`

P4 已经实现 `previewText`：`lastMessageType == "image" → "[图片]"`（`ConversationsListView.swift:199`）。`applyIncomingMessage` 把 WS 到达消息的 `messageType` 灌到 `lastMessageType`（`ConversationsListViewModel.swift:163`）。本任务只跑回归测试，确认 image 路径没问题。

- [ ] **Step 1: 在 `ConversationsListViewModelTests` 增加一个 image preview 回归测试（如果还没有）**

```bash
grep -n "image\|messageType\|lastMessageType" ios-app/EchoIMTests/ConversationsListViewModelTests.swift
```

如果没有相关测试，追加：

```swift
@Test
@MainActor
func incomingImageMessageUpdatesPreviewToImageType() async throws {
    let repo = MockConversationRepo()
    let initial = Conversation(
        id: 5,
        createdAt: Date(),
        peer: UserProfile(id: 9, username: "p", displayName: nil, avatarUrl: nil),
        lastMessageBody: "hi",
        lastMessageType: "text",
        lastMessageSenderId: 9,
        lastMessageAt: Date(timeIntervalSince1970: 1745000000),
        lastReadMessageId: nil,
        unreadCount: 0
    )
    repo.listResult = .success([initial])

    let vm = ConversationsListViewModel(
        repository: repo,
        metaStore: nil,
        tokenProvider: { "t" },
        currentUserId: { 3 }
    )
    await vm.refresh()

    vm.handleWSEvent(.messageNew(
        Message(
            id: 800, conversationId: 5, senderId: 9,
            body: nil, messageType: "image",
            mediaUrl: "/uploads/messages/9-1745800000000.jpg",
            createdAt: Date(), clientTempId: nil
        )
    ))

    let updated = try #require(vm.conversations.first)
    #expect(updated.lastMessageType == "image")
    #expect(updated.lastMessageBody == nil)
    #expect(updated.unreadCount == 1)
}
```

- [ ] **Step 2: 跑测试**

Run: `$TEST -only-testing:EchoIMTests/ConversationsListViewModelTests`
Expected: 全过；如果新增的 image 预览测试失败，回去检查 `applyIncomingMessage` 是否把 `lastMessageBody = nil` 透传——P4 实现的 `Conversation.updatedCopy` 用 `??` fallback，传 nil 就会保留旧 body。这个行为对 image 是 bug：image 没有 body 还显示旧 body 文字。如有，需要把 `Conversation.updatedCopy` 改为接收 `Optional<Optional<String>>` 区分"不传"vs"传 nil"。

> 但实测 P4 里 `applyIncomingMessage` 调用是：
>
> ```swift
> let updated = Conversation.updatedCopy(
>     of: old,
>     lastMessageBody: message.body,           // image 时 message.body == nil
>     lastMessageType: message.messageType,    // "image"
>     ...
> )
> ```
>
> `Conversation.updatedCopy` 的 `lastMessageBody: String? = nil` 默认参数是"不传"，但调用方实际**传了 nil**——这会触发 `??`，变成 "保留 old.lastMessageBody"。**这是 P4 的潜在 bug，本任务必须验证并修。**
>
> 修法：把 `updatedCopy` 改成 `Optional<Optional<String>>`，或者拆成两个签名。最干净的方法是再加一个 mutating helper 或者直接在 `applyIncomingMessage` 里手写：
>
> ```swift
> let updated = Conversation(
>     id: old.id,
>     createdAt: old.createdAt,
>     peer: old.peer,
>     lastMessageBody: message.body,         // 显式 nil（image 类型）
>     lastMessageType: message.messageType,
>     lastMessageSenderId: message.senderId,
>     lastMessageAt: message.createdAt,
>     lastReadMessageId: old.lastReadMessageId,
>     unreadCount: old.unreadCount + (shouldIncrementUnread ? 1 : 0)
> )
> ```
>
> 这是 P5 任务里**唯一一处对 P4 已有代码的修补**。如果回归测试在 Step 2 通过（说明 P4 实现已经正确处理 nil body），跳过；否则按上面替换 `applyIncomingMessage` 里的 updatedCopy 调用。

- [ ] **Step 3: 模拟器手工**

A 给 B 发文字 → ChatsList 显示文字预览。
A 给 B 发图片 → ChatsList 显示 `[图片]`，时间戳更新，未读数 +1。

- [ ] **Step 4: 提交（视情况只提交测试或 + bug 修复）**

```bash
git add ios-app/EchoIMTests/ConversationsListViewModelTests.swift \
         ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift
git commit -m "test(ios): regression coverage for image preview in ChatsList"
```

> 提交信息按实际改动调整（如果只加了测试没改实现，commit 信息保留 test 前缀；如果同时改了 bug，加上 `fix(ios): clear lastMessageBody when image message arrives`）。

---

## Task 13: XCUITest smoke — Image picker 入口可达

**Files:**
- Create: `ios-app/EchoIMUITests/ImageSendSmokeTests.swift`

XCUITest 触达不到系统 Photos picker UI（沙盒外）；只能断言"按钮存在 + 点击不 crash + Picker 模态出现"。

- [ ] **Step 1: 写 smoke 测试**

> 现有 UI 测试只有 `-uitest-reset-keychain` 这一个 launchArgument（`ChatSmokeTests.swift:11`），登录走"`loginEmail` → `loginPassword` → `loginSubmit`"手动填表单（参考 `ChatSmokeTests.swift:14-25`）。本任务沿用同一流程，**不**发明新的 launch args。`smoke@test.local` / `password123` 是 P3 引入的测试账号，假设 server 端已有数据；如果跑下来需要先注册，参考 `FriendRequestCrossAccountSmokeTests` 里的 `register(_:)` helper。

```swift
// ios-app/EchoIMUITests/ImageSendSmokeTests.swift
import XCTest

final class ImageSendSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImagePickerButtonOpensPhotosUI() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset-keychain"]
        app.launch()

        // 与 ChatSmokeTests 一致的登录流程
        let email = app.textFields["loginEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("smoke@test.local")

        let password = app.secureTextFields["loginPassword"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("password123")

        app.buttons["loginSubmit"].tap()

        let tabView = app.otherElements["mainTabView"]
        XCTAssertTrue(tabView.waitForExistence(timeout: 10))

        // 进会话列表 → 第一个会话
        let conversationsList = app.descendants(matching: .any)["conversationsList"]
        XCTAssertTrue(conversationsList.waitForExistence(timeout: 10))
        let firstRow = conversationsList.descendants(matching: .cell).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        firstRow.tap()

        // 输入栏的图片按钮
        let picker = app.buttons["chatImagePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        // PhotosPicker 模态属于另一个进程（com.apple.PhotosUI），
        // 只验证当前 app 不 crash + 仍处于前台。iOS 17 上 swipeDown 关闭模态。
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
        app.swipeDown(velocity: .fast)
    }
}
```

> 这个测试故意宽松——重点是"集成层不 crash"。完整 image flow 在 Task 11 的模拟器手工里覆盖。
>
> 当前 UI fixture 全集 grep：
>
> ```bash
> grep -rn "uitest\|launchArguments" ios-app/EchoIMUITests
> ```

- [ ] **Step 2: 跑 UI smoke**

Run: `$UITEST -only-testing:EchoIMUITests/ImageSendSmokeTests`
Expected: 通过。如果 fixture 名字不对，按 grep 结果改。

- [ ] **Step 3: 提交**

```bash
git add ios-app/EchoIMUITests/ImageSendSmokeTests.swift
git commit -m "test(ios): UI smoke for image picker entry"
```

---

## Task 14: 手工验收清单

**Files:**
- 无（纯手工）

执行 `$BUILD` 后用模拟器（或真机）跑一遍下列清单，全部通过才能进入 Self-Review。

### 14.1 文字 ↔ 图片混合发送

- [ ] A 给 B 发文字 → B 收到 → ChatsList 预览是文字
- [ ] A 给 B 发图片 → B 收到 → ChatsList 预览是 `[图片]`、未读数 +1
- [ ] A 给 B 在同一会话连发"文字 → 图片 → 文字" → 三条都按时间序排在 ChatView 末尾
- [ ] B 点开聊天 → 标已读 → 未读数清零

### 14.2 阶段化重试

- [ ] 关 Wi-Fi → A 选图 → 一两秒后 bubble 变 failed
- [ ] 验证 console 日志显示 upload 失败（用 `xcrun simctl spawn booted log stream`）
- [ ] 开 Wi-Fi → 点重试 → bubble 转 pending → 成功 → confirmed
- [ ] 第二个场景：让 upload 成功但 `POST /api/messages` 失败。**不要改 server 代码**（与"P5 不开 server task"原则一致）。可选验证手段，按可用性挑一种：
  - **A. 用 HTTP 代理（Charles / Proxyman）**：在 macOS 上挂代理，在 iOS Simulator 配置 HTTP proxy 指向 macOS，加一条规则 `POST localhost:3000/api/messages → 500`。开始测试前发图片，触发 messages 失败但 upload 已经写入 `uploads/messages/`。
  - **B. 临时把 server 杀掉的窗口很短**：先在 Simulator 选好图（PhotosPicker 弹出但还没点确认时图片已经 PHAsset 选定但未压缩），快速 `docker compose stop server` 后回到 Simulator 点确认。upload 会失败 → 这种方式实际是 14.2 第一种场景（upload 失败），**测不到"upload 成功 + send 失败"**，不算证据。
  - **C. 在 iOS 端临时改 ChatViewModel.executeImageSend，在 messageRepo.sendImage 调用前手动 throw**：本地编辑、不提交。验证 retry 时 `upload.uploadCalls == 1`、第二次 retry 通过后 server access log 只有一次 `/api/upload/message-image` 但有两次 `/api/messages`。这种方式不污染 server 仓库，是首选。
- [ ] 选 A 或 C 完成后：点重试 → 验证 server access log **没有**新的 `POST /api/upload/message-image`，只有 `POST /api/messages` —— 这是阶段化重试的关键证据。结束验证后还原本地改动（C 的 throw）/ 关闭代理规则（A）

### 14.3 不闪烁

- [ ] A 选图 → bubble 立即用本地 Data 渲染，pending overlay
- [ ] 服务端 201 回来 → overlay 消失，**图片本身不闪**（视觉无切换 / 重新加载）
- [ ] 滚到顶 → 滚回到底 → bubble 还是用 localImageData（B 的 bubble 走 Nuke，B 那一侧第一次加载有 spinner，再回来直接命中磁盘缓存秒出）

### 14.4 Lightbox

- [ ] 点 A 自己发的图片 → 全屏，`localImageData` 直出
- [ ] pinch zoom 工作；双击放大；再双击还原
- [ ] 点 B 发来的图片 → 全屏，从 Nuke 加载（首次有 spinner）
- [ ] 点 X 关闭 / 滑下关闭都能回 ChatView

### 14.5 草稿对话发图

- [ ] 从联系人列表点一个未聊过的好友 → 进入草稿态 ChatView（顶部 nav title 是好友名，输入栏可用）
- [ ] 直接发图片 → 服务端 201 回 conversation_id → bubble 变 confirmed → ChatsList 出现这个新会话

### 14.6 后台 / 重连

- [ ] 杀进程 → 重启 → 进同一会话 → 之前发的图片仍然显示（B 的图走 Nuke 磁盘缓存；A 的图走服务端 mediaUrl 远程加载，因为 localImageData 已丢失）
- [ ] 关 Wi-Fi → 切后台 5s → 开 Wi-Fi 切回前台 → connection.ready → cursor 翻页补拉这期间 B 发的图 → ChatView 末尾出现

### 14.7 多账号隔离

- [ ] A 登录 → 收到 B 的图片若干 → 登出
- [ ] B（同设备）登录 → A 的会话不出现、A 的图片缓存不出现
- [ ] 检查：`~/Library/Developer/CoreSimulator/.../Containers/Data/Application/<bundle>/Library/Application Support/EchoIM/users/` 目录下应该有两个独立子目录

### 14.8 清缓存

- [ ] Me 页 → 清除聊天缓存 → 回 ChatsList → 预览仍在（因为 ConversationsList 内存里有缓存了）
- [ ] 杀进程 → 重启 → 进会话 → 走场景 A 全量重拉
- [ ] Nuke 缓存清空（B 的图首次再加载是 spinner，不是即出）

---

## Self-Review（完成前必过）

- [ ] **P5 覆盖设计 §8 P5 全部要点**：
  - `UploadRepository.uploadMessageImage` → Task 3
  - `ImageCompressor`（1600px / JPEG 0.80 / 白底 flatten） → Task 1
  - `PhotosPicker` 接入输入栏 → Task 11
  - 设计 §6.3 阶段化重试 `ImageSendStage` → Task 5 / 6 / 7
  - `ImageMessageBubble` localData 优先 → Task 9
  - 全屏预览 pinch/zoom（`Lightbox` + `ZoomableImageView`） → Task 10
  - `ChatsList` 显示 `[图片]`（P4 已实现，Task 12 仅回归 + 修 P4 nil body 潜在 bug）
  - 收到对方图片走 Nuke 加载 → Task 9 `LazyImage(url:)`

- [ ] **Placeholder 扫描**：

```bash
grep -rn -iE "t[b]d|t[o]do|implement[ -]later|similar[ -]to[ -]task|\\.\\.\\." \
  docs/superpowers/plans/2026-04-25-ios-p5-image-messaging.md \
  | grep -v "^[^:]*:[0-9]*:[[:space:]]*//\?[[:space:]]*\\.\\.\\." \
  | grep -v "现有 .* 不变\|相同模式"
```
应为空（允许"// ... 现有 ... 不变"这类注释）。

- [ ] **类型一致性**（跨任务用到的符号必须自洽）：
  - `ImageCompressor.compressForUpload(_ image: UIImage) -> (data: Data, width: Int, height: Int)?` — Task 1 引入；Task 6 `sendImage(_ image: UIImage)` 使用
  - `UploadRepository.uploadMessageImage(data: Data, token: String) async throws -> String` — Task 3 引入；Task 5 / 6 / 7 / 11 使用
  - `MessageRepository.sendImage(recipientId: Int, mediaUrl: String, clientTempId: String, token: String) async throws -> Message` — Task 4 引入；Task 6 / 7 / 8 使用
  - `ImageSendStage` 的两个 case `.notStarted` / `.uploaded(mediaURL: String)` — Task 5 引入；Task 6 / 7 内部使用
  - `ChatViewModel.imageSendStages: [String: ImageSendStage]` — Task 5 引入；Task 6 / 7 / 8 测试断言
  - `ChatViewModel.sendImage(_ image: UIImage) async` / `sendCompressedImage(data: Data, width: Int, height: Int) async` — Task 6 引入；Task 11 调用 sendImage、测试调用 sendCompressedImage
  - `ChatViewModel.retry(localId: String)` — P3 已存在，Task 7 改造为按 messageType 分叉
  - `ChatView.init(... uploadRepo: UploadRepository, ...)` — Task 11 引入；MainTabView / ConversationsListView / ContactsView 使用
  - `UserSession.makeUploadRepository() -> UploadRepository` — Task 11 引入；MainTabView 使用
  - `Lightbox(localData:remoteURL:onClose:)` — Task 10 引入；Task 11 ChatView fullScreenCover 使用
  - `MessageBubble(message:isSelf:onRetry:onOpenImage:)` — Task 9 改造；Task 11 ChatView 调用

- [ ] **不变式 1（media_url 不要客户端拼）**：检查 `ChatViewModel.executeImageSend` 直接用 `uploadRepo` 返回值传给 `messageRepo.sendImage`，不做任何字符串处理。

- [ ] **不变式 2（multipart field name 必须是 `file`）**：`UploadRepositoryImpl.uploadMessageImage` 的 `makeMultipartBody(fieldName: "file", ...)`；Task 3 测试 `uploadMessageImageReturnsMediaURL` 已断言 body 含 `name="file"`。

- [ ] **不变式 3（白底 flatten 在 resize 之前）**：`ImageCompressor.compressForUpload` 里 `UIColor.white.setFill() → ctx.fill(rect) → image.draw(in: rect)` 顺序固定；Task 1 透明 PNG 测试已验证。

- [ ] **不变式 4（`UIGraphicsImageRendererFormat.scale = 1`）**：`ImageCompressor` 显式设置；Task 1 `resizesLongerEdgeTo1600WhenLarger` 测试间接验证（输出 width/height 等于 pt 数）。

- [ ] **不变式 5（mergeServerResult 保留 localImageData）**：`ChatViewModel.swift:271-280` 的 `mergeServerResult` 现有实现里 `localImageData: messages[index].localImageData` 一行不动；Task 8 `wsEchoFromSelfMergesIntoPendingImageBubblePreservingLocalData` 测试验证。

- [ ] **不变式 6（pending image 不写 SwiftData）**：`sendCompressedImage` 的 optimistic insert 路径**不**调用 `writeThroughAndMeta`；只有 `mergeServerResult` / `handleIncomingMessage` 的 confirmed 路径写盘。Task 8 `pendingImageBubbleIsNotWrittenToCache` 测试验证。

- [ ] **重试边界**：
  - Upload 失败 → stage = `.notStarted` → retry 重新上传 → ✓ Task 7 `retryRestartsFromUploadWhenStageIsNotStarted`
  - Send 失败 → stage = `.uploaded(...)` → retry 跳过上传 → ✓ Task 7 `retrySkipsUploadWhenStageIsUploaded`
  - localImageData 丢失 → retry no-op → ✓ Task 7 `retryNoOpsWhenLocalImageDataMissing`
  - 文字 retry 路径不退化 → P3 已有测试 + Task 7 Step 6 全套验证

- [ ] **`P4 已知妥协 → P5 接收**：
  - "VM 重建后 failed image 丢失"：本计划"已知妥协"段已写明
  - "压缩在主线程"：本计划"已知妥协"段已写明，留 Task.detached 升级路径
  - 没有 image schema migration（`CachedMessage.mediaUrl` P4 已有）：本计划"不在 P5 范围"段已写明

- [ ] **服务端契约 0 改动**：
  ```bash
  git diff main...HEAD -- server/ | grep -v "^$" | head
  ```
  应该为空。整个 P5 不应该有任何 server/ 下的改动。

- [ ] **`ChatViewModel` 测试 mock 同步更新**：所有 `class .*: MessageRepository` mock 都加了 `sendImage` 方法（Task 4 Step 5）。验证：
  ```bash
  grep -rn "func sendImage\|: MessageRepository {" ios-app/EchoIMTests
  ```
  每个 conform 都应有 `sendImage`。

- [ ] **`ChatView.init` 多了 uploadRepo 参数 → 三个调用方都更新**（Task 11 Step 4）：
  ```bash
  grep -rn "ChatView(" ios-app/EchoIM/Features ios-app/EchoIMUITests
  ```
  全部应包含 `uploadRepo:`。

- [ ] **Lint**：（与 P1-P4 一致）
  - 服务端：未改，无需跑
  - iOS：`$BUILD` warning 为零
  - 检查：`xcodebuild ... build 2>&1 | grep -i 'warning'`，应只有第三方包内部 warning

- [ ] **工作目录一致**：所有路径以 `ios-app/EchoIM/...` 开头，无裸相对路径。

---

## 未来阶段的依赖锚点（给 P6+ 计划起草人）

**P6（Presence + Typing）会触及本阶段的文件**：
- `ChatViewModel.handleWSEvent` 的 `default:` 分支已经在 P3 留了占位（"return"）；P6 会在该 switch 加 `case .typingStart` / `.typingStop` / `.presenceOnline` / `.presenceOffline`。P5 不增加 WSEvent 类型。
- `UserSession` P5 增加了 `makeUploadRepository`；P6 会再加 `presenceStore` / `typingStore` 这两个 `@Observable` 单例（设计 §2.2 已预留 `let presenceStore = PresenceStore()`），不影响 P5 已写的工厂方法。

**P7（Profile 编辑 + 头像上传）会触及本阶段的文件**：
- `UploadRepository` 加 `uploadAvatar(data: Data, token: String) async throws -> String` 方法，参数对齐服务端 `AVATAR_CONFIG`（400px 方形 / JPEG 0.80）；`ImageCompressor` 加 `compressForAvatar(_ image: UIImage) -> ...`（中心裁剪 + 1:1 缩放到 400px + 白底 flatten + JPEG 0.80）。P7 的 multipart body 路径完全复用 P5 的 `APIClient.upload` 与 `makeMultipartBody`，field name 也是 `avatar`（与 server `upload.ts:32` 对齐）——P7 起草人记得改 field name + filename，不要复制粘贴 `"image.jpg"`。

**P8（打磨 + 测试 + Dark Mode）会触及本阶段的文件**：
- `ImageMessageBubble` 在 Dark Mode 下的边角 / 占位色需检查（Task 14 手工冒烟里只跑了 Light Mode）
- `Lightbox` 黑底在 Light Mode 已经够；Dark Mode 下保持黑底，导航栏 contrast 检查
- 压缩耗时实测：`ImageCompressor.compressForUpload` 跑 Instruments time profile，确认 P95 < 200ms；超过的话迁到 `Task.detached`（已知妥协里有铺垫）

**P5 引入的设计债**：
- **fire-and-forget upload 没有进度反馈**：bubble 只显示 spinner、不显示百分比。P8 加 `URLSessionTaskDelegate.didSendBodyData` 监听并把进度灌回 `LocalMessage`（要给 `LocalMessage` 加 `uploadProgress: Double?` 字段）。
- **PhotosPicker 选完图后用户切走聊天页 → 当前没有取消机制**：`onChange(of: pickedItem)` 触发的 `Task` 会继续跑（压缩 + 上传 + 发送），如果在 ChatViewModel 销毁前完成，结果会被静默丢弃；如果在销毁后完成，service 端仍然收到了消息，但本端 UI 不显示。这个跟 Web 端的行为对齐（Web 也是 Promise 跑完为止），不算 bug 但需要在 P8 的"已知限制"里写一笔。
- **Lightbox 不持久化缩放**：每次进入都从 fit 开始；P8 视情况加 zoomScale 记忆（也可不做）。
- **Image schema migration 未演练**：`CachedMessage.mediaUrl` P4 就有，P5 没新增字段。第一次真正动 schema 是未来 P6 / P7 引入新字段时（如 `imageWidth` / `imageHeight` / `avatarLocalPath`）；那时需要引入 `VersionedSchema` + `SchemaMigrationPlan`（P4 self-review 里已经标过这个 TODO）。
