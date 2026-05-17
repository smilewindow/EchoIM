# API 错误协议实施计划

> **给执行代理的要求：** 实施本计划时必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，并按任务逐项执行。步骤使用 checkbox（`- [ ]`）追踪进度。

**目标：** 将 EchoIM 升级为结构化 API 错误协议，并让 iOS 对 HTTP/API 请求失败展示本地化 toast。

**架构：** 后台集中维护稳定的 `snake_case` 错误码和英文 fallback message；iOS 解析结构化错误，用错误码映射本地化文案，并通过全局 toast 展示 HTTP/API 失败。后台和 iOS 必须同批完成，因为这是 breaking API contract。

**技术栈：** Fastify 5、TypeScript、Vitest、Swift 6、SwiftUI Observation、Xcode file-system synchronized groups。

---

## 参考设计

- `docs/superpowers/specs/2026-05-17-api-error-contract-design.md`

## 文件结构

后台文件：

- 新建 `server/src/lib/api-errors.ts`：集中定义错误码、英文 fallback message 和 `sendApiError`。
- 修改 `server/src/app.ts`：统一 Fastify/AJV 校验错误和 500 错误返回。
- 修改 `server/src/hooks/authenticate.ts`：结构化鉴权错误。
- 修改 `server/src/routes/auth.ts`：结构化登录/注册业务错误。
- 修改 `server/src/routes/friend-requests.ts`：结构化好友申请错误。
- 修改 `server/src/routes/messages.ts`：结构化发消息错误。
- 修改 `server/src/routes/conversations.ts`：结构化会话/已读错误。
- 修改 `server/src/routes/users.ts`：结构化用户资料错误。
- 修改 `server/src/routes/upload.ts`：结构化上传错误。
- 修改 `server/tests/helpers.ts`：新增 `expectApiError`。
- 修改 `server/tests/*.test.ts`：断言状态码和字面量 `code`。

iOS 文件：

- 修改 `ios-app/EchoIM/Core/Networking/APIError.swift`：从 HTTP body 解析结构化服务端错误。
- 新建 `ios-app/EchoIM/Core/Networking/ErrorPresenter.swift`：把 `APIError` 和服务端 `code` 映射为本地化展示文案。
- 新建 `ios-app/EchoIM/Core/UI/ToastCenter.swift`：全局 toast 状态和自动消失逻辑。
- 新建 `ios-app/EchoIM/Core/UI/ToastOverlay.swift`：复用 SwiftUI toast 样式。
- 修改 `ios-app/EchoIM/App/AppContainer.swift`：持有一个 `ToastCenter`。
- 修改 `ios-app/EchoIM/App/RootView.swift`：统一渲染全局 toast。
- 修改现有会发 HTTP/API 请求的 ViewModel/View，让失败走 toast：
  - `ios-app/EchoIM/Features/Auth/LoginViewModel.swift`
  - `ios-app/EchoIM/Features/Auth/RegisterViewModel.swift`
  - `ios-app/EchoIM/Features/Conversations/ConversationsListViewModel.swift`
  - `ios-app/EchoIM/Features/Conversations/ConversationsListView.swift`
  - `ios-app/EchoIM/Features/Contacts/ContactsViewModel.swift`
  - `ios-app/EchoIM/Features/Contacts/ContactsView.swift`
  - `ios-app/EchoIM/Features/Contacts/UserSearchSheetView.swift`
  - `ios-app/EchoIM/Features/Chat/ChatViewModel.swift`
  - `ios-app/EchoIM/Features/Chat/ChatView.swift`
  - `ios-app/EchoIM/Features/Me/ProfileEditViewModel.swift`
  - `ios-app/EchoIM/Features/Me/ProfileEditView.swift`
- 修改 `ios-app/EchoIM/Localizable.xcstrings`：新增 API 错误文案的中英文映射。
- 修改或新增 `ios-app/EchoIMTests` 下测试：覆盖错误解析、本地化 fallback、代表性 ViewModel toast 回调。

Xcode 注意事项：当前工程使用 `PBXFileSystemSynchronizedRootGroup`，在 `ios-app/EchoIM/...` 下新增 Swift 文件不需要手工改 `project.pbxproj` 的 source-file entries。

---

### Task 1: 后台错误定义和测试 helper

**文件：**
- 新建：`server/src/lib/api-errors.ts`
- 修改：`server/tests/helpers.ts`

- [ ] **Step 1: 新增集中错误定义**

创建 `server/src/lib/api-errors.ts`：

```ts
import type { FastifyReply } from 'fastify'

export type ApiErrorDefinition = {
  statusCode: number
  code: string
  message: string
}

export type ApiErrorResponse = {
  error: {
    code: string
    message: string
  }
}

export const ApiErrors = {
  invalidRequest: {
    statusCode: 400,
    code: 'invalid_request',
    message: 'Invalid request',
  },
  internalError: {
    statusCode: 500,
    code: 'internal_error',
    message: 'Internal server error',
  },
  authMissing: {
    statusCode: 401,
    code: 'auth_missing',
    message: 'Missing or invalid Authorization header',
  },
  authInvalid: {
    statusCode: 401,
    code: 'auth_invalid',
    message: 'Invalid or expired token',
  },
  authInvalidPayload: {
    statusCode: 401,
    code: 'auth_invalid_payload',
    message: 'Invalid token payload',
  },
  invalidInviteCode: {
    statusCode: 403,
    code: 'invalid_invite_code',
    message: 'Invalid invite code',
  },
  usernameTooShort: {
    statusCode: 400,
    code: 'username_too_short',
    message: 'Username must be at least 3 characters',
  },
  invalidEmail: {
    statusCode: 400,
    code: 'invalid_email',
    message: 'Invalid email address',
  },
  emailAlreadyInUse: {
    statusCode: 409,
    code: 'email_already_in_use',
    message: 'Email already in use',
  },
  usernameAlreadyTaken: {
    statusCode: 409,
    code: 'username_already_taken',
    message: 'Username already taken',
  },
  accountAlreadyExists: {
    statusCode: 409,
    code: 'account_already_exists',
    message: 'Account already exists',
  },
  invalidCredentials: {
    statusCode: 401,
    code: 'invalid_credentials',
    message: 'Invalid email or password',
  },
  userNotFound: {
    statusCode: 401,
    code: 'user_not_found',
    message: 'User no longer exists',
  },
  noFieldsToUpdate: {
    statusCode: 400,
    code: 'no_fields_to_update',
    message: 'No fields to update',
  },
  friendRequestSelf: {
    statusCode: 400,
    code: 'friend_request_self',
    message: 'Cannot send friend request to yourself',
  },
  recipientNotFound: {
    statusCode: 404,
    code: 'recipient_not_found',
    message: 'Recipient not found',
  },
  friendRequestAlreadyExists: {
    statusCode: 409,
    code: 'friend_request_already_exists',
    message: 'Friend request already exists',
  },
  friendRequestNotFound: {
    statusCode: 404,
    code: 'friend_request_not_found',
    message: 'Friend request not found',
  },
  messageBodyRequired: {
    statusCode: 400,
    code: 'message_body_required',
    message: 'Body is required for text messages',
  },
  messageMediaRequired: {
    statusCode: 400,
    code: 'message_media_required',
    message: 'Media URL is required for image messages',
  },
  messageMediaInvalid: {
    statusCode: 400,
    code: 'message_media_invalid',
    message: 'Invalid media URL',
  },
  messageDimensionsInvalid: {
    statusCode: 400,
    code: 'message_dimensions_invalid',
    message: 'Media width and height must be provided together',
  },
  notFriends: {
    statusCode: 403,
    code: 'not_friends',
    message: 'You can only send messages to friends',
  },
  invalidConversationId: {
    statusCode: 400,
    code: 'invalid_conversation_id',
    message: 'Invalid conversation id',
  },
  paginationCursorConflict: {
    statusCode: 400,
    code: 'pagination_cursor_conflict',
    message: 'Cannot use both before and after',
  },
  conversationNotFound: {
    statusCode: 404,
    code: 'conversation_not_found',
    message: 'Conversation not found',
  },
  invalidLastReadMessageId: {
    statusCode: 400,
    code: 'invalid_last_read_message_id',
    message: 'Invalid last_read_message_id',
  },
  fileRequired: {
    statusCode: 400,
    code: 'file_required',
    message: 'No file provided',
  },
  invalidImageFile: {
    statusCode: 400,
    code: 'invalid_image_file',
    message: 'Invalid image file',
  },
} as const satisfies Record<string, ApiErrorDefinition>

export function sendApiError(reply: FastifyReply, error: ApiErrorDefinition) {
  return reply.status(error.statusCode).send({
    error: {
      code: error.code,
      message: error.message,
    },
  } satisfies ApiErrorResponse)
}
```

- [ ] **Step 2: 新增测试 helper**

修改 `server/tests/helpers.ts`，加入 import：

```ts
import { expect } from 'vitest'
```

在文件末尾添加：

```ts
type ApiErrorTestResponse = {
  statusCode: number
  json: () => unknown
}

export function expectApiError(
  res: ApiErrorTestResponse,
  statusCode: number,
  code: string,
) {
  expect(res.statusCode).toBe(statusCode)

  const body = res.json() as { error?: { code?: unknown; message?: unknown } }
  expect(body).toEqual({
    error: {
      code,
      message: expect.any(String),
    },
  })
  expect(body.error?.message).not.toBe('')
}
```

说明：测试里传字面量 `code`，不要传 `ApiErrors.xxx.code`。这是为了锁住对外 API 契约，避免后端误改错误码但测试仍然通过，导致 iOS 本地化映射失效。

- [ ] **Step 3: 后台类型检查**

运行：

```bash
npm run build --prefix server
```

预期：PASS。

- [ ] **Step 4: 提交**

```bash
git add server/src/lib/api-errors.ts server/tests/helpers.ts
git commit -m "feat: add structured API error helper"
```

---

### Task 2: 全局错误和鉴权/Auth 错误

**文件：**
- 修改：`server/src/app.ts`
- 修改：`server/src/hooks/authenticate.ts`
- 修改：`server/src/routes/auth.ts`
- 修改：`server/tests/auth.test.ts`
- 修改：`server/tests/users.test.ts`

- [ ] **Step 1: 先写失败测试**

修改 `server/tests/auth.test.ts` import：

```ts
import { getApp, truncateAll, registerUser, getInviteCode, expectApiError } from './helpers.js'
```

把代表性错误断言改成：

```ts
expectApiError(res, 409, 'email_already_in_use')
expectApiError(res, 409, 'username_already_taken')
expectApiError(res, 401, 'invalid_credentials')
expectApiError(res, 400, 'invalid_request')
```

修改 `server/tests/users.test.ts` import：

```ts
import { getApp, truncateAll, registerUser, expectApiError } from './helpers.js'
```

未登录请求断言：

```ts
expectApiError(res, 401, 'auth_missing')
```

- [ ] **Step 2: 确认测试会失败**

运行：

```bash
npm test --prefix server -- auth.test.ts users.test.ts
```

预期：FAIL，因为当前后台仍返回旧的 `{ error: string }`。

- [ ] **Step 3: 改全局错误处理**

修改 `server/src/app.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from './lib/api-errors.js'
```

替换 `setErrorHandler`：

```ts
app.setErrorHandler((err: FastifyError, _request, reply) => {
  const statusCode = err.statusCode ?? 500

  if (statusCode >= 400 && statusCode < 500) {
    return sendApiError(reply, ApiErrors.invalidRequest)
  }

  app.log.error(err)
  return sendApiError(reply, ApiErrors.internalError)
})
```

说明：Fastify/AJV schema 校验错误统一返回 `invalid_request`，不把技术化 message 透传给客户端。

- [ ] **Step 4: 改鉴权 hook**

修改 `server/src/hooks/authenticate.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

替换三个鉴权失败：

```ts
return sendApiError(reply, ApiErrors.authMissing)
return sendApiError(reply, ApiErrors.authInvalid)
return sendApiError(reply, ApiErrors.authInvalidPayload)
```

- [ ] **Step 5: 改 Auth 路由**

修改 `server/src/routes/auth.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

替换错误返回：

```ts
return sendApiError(reply, ApiErrors.invalidInviteCode)
return sendApiError(reply, ApiErrors.usernameTooShort)
return sendApiError(reply, ApiErrors.invalidEmail)
return sendApiError(reply, ApiErrors.emailAlreadyInUse)
return sendApiError(reply, ApiErrors.usernameAlreadyTaken)
return sendApiError(reply, ApiErrors.accountAlreadyExists)
return sendApiError(reply, ApiErrors.invalidCredentials)
```

- [ ] **Step 6: 跑聚焦测试**

运行：

```bash
npm test --prefix server -- auth.test.ts users.test.ts
```

预期：PASS。

- [ ] **Step 7: 提交**

```bash
git add server/src/app.ts server/src/hooks/authenticate.ts server/src/routes/auth.ts server/tests/auth.test.ts server/tests/users.test.ts
git commit -m "feat: structure auth API errors"
```

---

### Task 3: 后台业务路由错误

**文件：**
- 修改：`server/src/routes/friend-requests.ts`
- 修改：`server/src/routes/messages.ts`
- 修改：`server/src/routes/conversations.ts`
- 修改：`server/src/routes/users.ts`
- 修改：`server/src/routes/upload.ts`
- 修改：`server/tests/friends.test.ts`
- 修改：`server/tests/messages.test.ts`
- 修改：`server/tests/upload.test.ts`
- 修改：`server/tests/users.test.ts`

- [ ] **Step 1: 先写失败测试**

各测试文件按需在 import 中加入 `expectApiError`：

```ts
import { getApp, truncateAll, registerUser, expectApiError } from './helpers.js'
```

根据场景使用这些字面量错误码断言：

```ts
expectApiError(res, 400, 'friend_request_self')
expectApiError(res, 404, 'recipient_not_found')
expectApiError(res, 409, 'friend_request_already_exists')
expectApiError(res, 404, 'friend_request_not_found')
expectApiError(res, 400, 'message_body_required')
expectApiError(res, 400, 'message_media_required')
expectApiError(res, 400, 'message_media_invalid')
expectApiError(res, 400, 'message_dimensions_invalid')
expectApiError(res, 403, 'not_friends')
expectApiError(res, 400, 'invalid_conversation_id')
expectApiError(res, 400, 'pagination_cursor_conflict')
expectApiError(res, 404, 'conversation_not_found')
expectApiError(res, 400, 'invalid_last_read_message_id')
expectApiError(res, 400, 'file_required')
expectApiError(res, 400, 'invalid_image_file')
expectApiError(res, 401, 'user_not_found')
expectApiError(res, 400, 'no_fields_to_update')
```

- [ ] **Step 2: 确认测试会失败**

运行：

```bash
npm test --prefix server -- friends.test.ts messages.test.ts users.test.ts upload.test.ts
```

预期：FAIL，因为业务路由仍是旧错误结构。

- [ ] **Step 3: 改好友申请路由**

修改 `server/src/routes/friend-requests.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

替换错误返回：

```ts
return sendApiError(reply, ApiErrors.friendRequestSelf)
return sendApiError(reply, ApiErrors.recipientNotFound)
return sendApiError(reply, ApiErrors.friendRequestAlreadyExists)
return sendApiError(reply, ApiErrors.invalidRequest)
return sendApiError(reply, ApiErrors.friendRequestNotFound)
```

`Not found or already resolved` 统一使用 `friendRequestNotFound`。好友申请冲突暂不细分，统一使用 `friendRequestAlreadyExists`。

- [ ] **Step 4: 改消息路由**

修改 `server/src/routes/messages.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

替换错误返回：

```ts
return sendApiError(reply, ApiErrors.messageBodyRequired)
return sendApiError(reply, ApiErrors.messageMediaRequired)
return sendApiError(reply, ApiErrors.messageMediaInvalid)
return sendApiError(reply, ApiErrors.messageDimensionsInvalid)
return sendApiError(reply, ApiErrors.notFriends)
```

- [ ] **Step 5: 改会话路由**

修改 `server/src/routes/conversations.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

替换错误返回：

```ts
return sendApiError(reply, ApiErrors.invalidConversationId)
return sendApiError(reply, ApiErrors.paginationCursorConflict)
return sendApiError(reply, ApiErrors.conversationNotFound)
return sendApiError(reply, ApiErrors.invalidLastReadMessageId)
```

成员校验失败继续返回 404，并使用 `conversationNotFound`，保持“隐藏资源存在性”的策略。

- [ ] **Step 6: 改用户路由**

修改 `server/src/routes/users.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

替换错误返回：

```ts
return sendApiError(reply, ApiErrors.userNotFound)
return sendApiError(reply, ApiErrors.noFieldsToUpdate)
```

- [ ] **Step 7: 改上传路由**

修改 `server/src/routes/upload.ts`，新增 import：

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

替换错误返回：

```ts
return sendApiError(reply, ApiErrors.fileRequired)
return sendApiError(reply, ApiErrors.invalidImageFile)
return sendApiError(reply, ApiErrors.userNotFound)
```

- [ ] **Step 8: 扫描旧错误结构**

运行：

```bash
rg "send\\(\\{ error: '" server/src server/tests
```

预期：无匹配。

运行：

```bash
rg "send\\(\\{ error: \\\"" server/src server/tests
```

预期：无匹配。

- [ ] **Step 9: 后台全量验证**

运行：

```bash
npm test --prefix server
npm run build --prefix server
npm run lint --prefix server
```

预期：PASS。

- [ ] **Step 10: 提交**

```bash
git add server/src server/tests
git commit -m "feat: structure backend business errors"
```

---

### Task 4: iOS 解析结构化服务端错误

**文件：**
- 修改：`ios-app/EchoIM/Core/Networking/APIError.swift`
- 修改：`ios-app/EchoIM/Features/Auth/AuthRepository.swift`
- 修改：`ios-app/EchoIMTests/APIErrorTests.swift`
- 修改：`ios-app/EchoIMTests/AuthRepositoryTests.swift`

- [ ] **Step 1: 先写失败测试**

在 `ios-app/EchoIMTests/APIErrorTests.swift` 中追加：

```swift
@Test
func decodesStructuredServerErrorFromHTTPBody() throws {
    let body = """
    {
      "error": {
        "code": "friend_request_already_exists",
        "message": "Friend request already exists"
      }
    }
    """.data(using: .utf8)!
    let error = APIError.http(status: 409, body: body)

    #expect(error.serverError?.code == "friend_request_already_exists")
    #expect(error.serverError?.message == "Friend request already exists")
}

@Test
func fallsBackWhenHTTPBodyIsMalformed() {
    let error = APIError.http(status: 500, body: Data("oops".utf8))

    #expect(error.serverError == nil)
}
```

- [ ] **Step 2: 确认测试会失败**

运行：

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests
```

预期：FAIL，因为 `serverError` 还不存在。

- [ ] **Step 3: 实现结构化错误解析**

修改 `ios-app/EchoIM/Core/Networking/APIError.swift`：

```swift
import Foundation

struct ServerAPIError: Decodable, Equatable, Sendable {
    let code: String
    let message: String
}

private struct ServerAPIErrorEnvelope: Decodable {
    let error: ServerAPIError
}

enum APIError: Error, Equatable {
    case network(URLError)
    case unauthorized
    case http(status: Int, body: Data)
    case decoding(String)
    case invalidResponse

    var serverError: ServerAPIError? {
        guard case .http(_, let body) = self else { return nil }
        return Self.decodeServerError(from: body)
    }

    static func decodeServerError(from body: Data) -> ServerAPIError? {
        guard !body.isEmpty else { return nil }
        return try? APIClient.jsonDecoder.decode(ServerAPIErrorEnvelope.self, from: body).error
    }

    static func fromStatus(_ status: Int, body: Data) -> APIError {
        if status == 401 {
            return .unauthorized
        }

        return .http(status: status, body: body)
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.network(let lhsError), .network(let rhsError)):
            return lhsError.code == rhsError.code
        case (.unauthorized, .unauthorized):
            return true
        case (.http(let lhsStatus, let lhsBody), .http(let rhsStatus, let rhsBody)):
            return lhsStatus == rhsStatus && lhsBody == rhsBody
        case (.decoding(let lhsMessage), .decoding(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.invalidResponse, .invalidResponse):
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: 更新 AuthRepository 解析**

修改 `AuthRepository.extractErrorMessage(_:)`，只解析新结构；不兼容旧 `{ "error": "..." }`：

```swift
nonisolated private static func extractErrorMessage(_ body: Data) -> String {
    if let serverError = APIError.decodeServerError(from: body) {
        return serverError.message
    }

    return String(data: body, encoding: .utf8) ?? ""
}
```

- [ ] **Step 5: 跑聚焦 iOS 测试**

运行：

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests -only-testing:EchoIMTests/AuthRepositoryTests
```

预期：PASS。

- [ ] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Core/Networking/APIError.swift ios-app/EchoIM/Features/Auth/AuthRepository.swift ios-app/EchoIMTests/APIErrorTests.swift ios-app/EchoIMTests/AuthRepositoryTests.swift
git commit -m "feat: decode structured API errors on iOS"
```

---

### Task 5: iOS 错误文案映射和本地化

**文件：**
- 新建：`ios-app/EchoIM/Core/Networking/ErrorPresenter.swift`
- 修改：`ios-app/EchoIM/Localizable.xcstrings`
- 新建：`ios-app/EchoIMTests/ErrorPresenterTests.swift`

- [ ] **Step 1: 先写失败测试**

创建 `ios-app/EchoIMTests/ErrorPresenterTests.swift`：

```swift
import Foundation
import Testing
@testable import EchoIM

@Suite("ErrorPresenter")
struct ErrorPresenterTests {
    @Test
    func mapsKnownServerCodeToLocalizedMessage() {
        let body = """
        {
          "error": {
            "code": "friend_request_already_exists",
            "message": "Friend request already exists"
          }
        }
        """.data(using: .utf8)!
        let error = APIError.http(status: 409, body: body)

        #expect(ErrorPresenter.message(for: error) == "好友申请已存在")
    }

    @Test
    func fallsBackToServerMessageForUnknownServerCode() {
        let body = """
        {
          "error": {
            "code": "new_server_code",
            "message": "New server fallback"
          }
        }
        """.data(using: .utf8)!
        let error = APIError.http(status: 499, body: body)

        #expect(ErrorPresenter.message(for: error) == "New server fallback")
    }

    @Test
    func mapsNetworkErrorLocally() {
        let error = APIError.network(URLError(.notConnectedToInternet))

        #expect(ErrorPresenter.message(for: error) == "网络不可用，请检查连接")
    }
}
```

- [ ] **Step 2: 确认测试会失败**

运行：

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ErrorPresenterTests
```

预期：FAIL，因为 `ErrorPresenter` 还不存在。

- [ ] **Step 3: 实现 ErrorPresenter**

创建 `ios-app/EchoIM/Core/Networking/ErrorPresenter.swift`：

```swift
import Foundation

enum ErrorPresenter {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return message(for: apiError)
        }

        return String(localized: "操作失败，请稍后重试")
    }

    static func message(for error: APIError) -> String {
        if let serverError = error.serverError {
            return message(forServerCode: serverError.code) ?? serverError.message
        }

        switch error {
        case .network(let urlError):
            switch urlError.code {
            case .notConnectedToInternet:
                return String(localized: "网络不可用，请检查连接")
            case .timedOut:
                return String(localized: "请求超时，请稍后重试")
            default:
                return String(localized: "网络错误，请稍后重试")
            }
        case .unauthorized:
            return String(localized: "登录状态已失效，请重新登录")
        case .http:
            return String(localized: "请求失败，请稍后重试")
        case .decoding, .invalidResponse:
            return String(localized: "数据异常，请稍后重试")
        }
    }

    static func message(forServerCode code: String) -> String? {
        switch code {
        case "invalid_invite_code":
            return String(localized: "邀请码无效")
        case "username_too_short":
            return String(localized: "用户名至少需要 3 个字符")
        case "invalid_email":
            return String(localized: "邮箱格式不正确")
        case "email_already_in_use":
            return String(localized: "邮箱已被使用")
        case "username_already_taken":
            return String(localized: "用户名已被占用")
        case "account_already_exists":
            return String(localized: "账号已存在")
        case "invalid_credentials":
            return String(localized: "邮箱或密码错误")
        case "user_not_found", "auth_missing", "auth_invalid", "auth_invalid_payload":
            return String(localized: "登录状态已失效，请重新登录")
        case "no_fields_to_update":
            return String(localized: "没有可保存的修改")
        case "friend_request_self":
            return String(localized: "不能添加自己为好友")
        case "recipient_not_found":
            return String(localized: "用户不存在")
        case "friend_request_already_exists":
            return String(localized: "好友申请已存在")
        case "friend_request_not_found":
            return String(localized: "好友申请不存在或已处理")
        case "message_body_required":
            return String(localized: "消息内容不能为空")
        case "message_media_required", "message_media_invalid":
            return String(localized: "图片消息无效，请重新选择")
        case "message_dimensions_invalid":
            return String(localized: "图片尺寸信息无效，请重新选择")
        case "not_friends":
            return String(localized: "只能给好友发送消息")
        case "invalid_conversation_id", "conversation_not_found":
            return String(localized: "会话不存在")
        case "pagination_cursor_conflict", "invalid_last_read_message_id", "invalid_request":
            return String(localized: "请求参数无效，请重试")
        case "file_required":
            return String(localized: "请选择要上传的文件")
        case "invalid_image_file":
            return String(localized: "图片文件无效，请重新选择")
        case "internal_error":
            return String(localized: "服务器开小差了，请稍后重试")
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: 新增本地化 key**

修改 `ios-app/EchoIM/Localizable.xcstrings`，给 `ErrorPresenter` 中引用但文件里还没有的中文 key 添加英文翻译。

最少需要添加这些：

```json
"好友申请已存在" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Friend request already exists"
      }
    }
  }
},
"网络不可用，请检查连接" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Network unavailable. Check your connection."
      }
    }
  }
},
"请求超时，请稍后重试" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Request timed out. Try again later."
      }
    }
  }
},
"数据异常，请稍后重试" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Unexpected data. Try again later."
      }
    }
  }
},
"服务器开小差了，请稍后重试" : {
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "Server error. Try again later."
      }
    }
  }
}
```

同时补齐 `ErrorPresenter.message(forServerCode:)` 里其它新增中文 key。不要修改已有无关翻译。

- [ ] **Step 5: 跑聚焦测试**

运行：

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ErrorPresenterTests
```

预期：PASS。

- [ ] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Core/Networking/ErrorPresenter.swift ios-app/EchoIM/Localizable.xcstrings ios-app/EchoIMTests/ErrorPresenterTests.swift
git commit -m "feat: localize iOS API errors"
```

---

### Task 6: iOS 全局 toast 能力

**文件：**
- 新建：`ios-app/EchoIM/Core/UI/ToastCenter.swift`
- 新建：`ios-app/EchoIM/Core/UI/ToastOverlay.swift`
- 修改：`ios-app/EchoIM/App/AppContainer.swift`
- 修改：`ios-app/EchoIM/App/RootView.swift`

- [ ] **Step 1: 新建 ToastCenter**

创建 `ios-app/EchoIM/Core/UI/ToastCenter.swift`：

```swift
import Foundation
import Observation

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String) {
        dismissTask?.cancel()
        current = ToastMessage(message: message)

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                current = nil
            }
        }
    }

    func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
}
```

- [ ] **Step 2: 新建 ToastOverlay**

创建 `ios-app/EchoIM/Core/UI/ToastOverlay.swift`：

```swift
import SwiftUI

struct ToastOverlay: View {
    let toast: ToastMessage

    var body: some View {
        Text(toast.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.78), in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
            .padding(.horizontal, 32)
            .accessibilityIdentifier("globalToast")
    }
}
```

- [ ] **Step 3: AppContainer 持有 ToastCenter**

修改 `ios-app/EchoIM/App/AppContainer.swift`，添加属性：

```swift
let toastCenter: ToastCenter
```

在 `init` 中初始化：

```swift
self.toastCenter = ToastCenter()
```

添加便捷方法：

```swift
func showErrorToast(for error: Error) {
    toastCenter.show(ErrorPresenter.message(for: error))
}

func showToast(_ message: String) {
    toastCenter.show(message)
}
```

在 `handleUnauthorized()` 里设置 `sessionExpiredNoticeID = UUID()` 后追加：

```swift
toastCenter.show(String(localized: "登录状态已失效，请重新登录"))
```

- [ ] **Step 4: RootView 改成全局 toast overlay**

修改 `ios-app/EchoIM/App/RootView.swift`。

移除：

```swift
@State private var sessionExpiredToastVisible = false
@State private var toastDismissTask: Task<Void, Never>?
```

移除原来监听 `container.sessionExpiredNoticeID` 控制私有 toast 的 `.onChange`。

替换 overlay：

```swift
.overlay {
    if let toast = container.toastCenter.current {
        ToastOverlay(toast: toast)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
.animation(.easeOut(duration: 0.18), value: container.toastCenter.current?.id)
```

删除私有 `sessionExpiredToast(_:)` 方法。

- [ ] **Step 5: 构建 iOS App**

运行：

```bash
xcodebuild build -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'
```

预期：PASS。

- [ ] **Step 6: 提交**

```bash
git add ios-app/EchoIM/Core/UI/ToastCenter.swift ios-app/EchoIM/Core/UI/ToastOverlay.swift ios-app/EchoIM/App/AppContainer.swift ios-app/EchoIM/App/RootView.swift
git commit -m "feat: add global iOS toast surface"
```

---

### Task 7: iOS HTTP/API 失败接入 toast

**文件：**
- 修改：上文文件结构里列出的相关 ViewModel 和 View。
- 修改：`ios-app/EchoIMTests` 中代表性测试。

- [ ] **Step 1: 给 ViewModel 添加错误回调**

对执行 HTTP/API 请求的 ViewModel 添加：

```swift
private let onError: @MainActor (Error) -> Void
```

初始化参数添加默认 no-op：

```swift
onError: @escaping @MainActor (Error) -> Void = { _ in }
```

保存：

```swift
self.onError = onError
```

需要 toast 的 catch 中调用：

```swift
onError(error)
```

至少应用到：

- `ConversationsListViewModel`
- `ContactsViewModel`
- `ChatViewModel`
- `ProfileEditViewModel`

- [ ] **Step 2: Auth 继续保留现有字符串状态，但未知错误走 ErrorPresenter**

修改 `LoginViewModel` 和 `RegisterViewModel`：

- 已有 `AuthError` 映射继续保留，保护登录/注册现有 UX。
- 非预期错误使用：

```swift
toast = ErrorPresenter.message(for: error)
```

- [ ] **Step 3: 从 View 传入 ToastCenter**

组装 feature view model 时传入：

```swift
onError: { [toastCenter = container.toastCenter] error in
    toastCenter.show(ErrorPresenter.message(for: error))
}
```

没有直接持有 `container` 的 View，从 `MainTabView` 显式向下传 `toastCenter`：

```swift
ConversationsListView(..., toastCenter: container.toastCenter, ...)
ContactsView(..., toastCenter: container.toastCenter, ...)
ChatView(..., toastCenter: container.toastCenter, ...)
ProfileEditView(..., toastCenter: container.toastCenter, ...)
```

- [ ] **Step 4: UserSearchSheetView 从 alert 改 toast**

移除：

```swift
@State private var errorToast: String?
```

添加：

```swift
let toastCenter: ToastCenter
```

发送好友申请失败：

```swift
if case .failure(let error) = result {
    toastCenter.show(ErrorPresenter.message(for: error))
}
```

搜索失败：

```swift
} catch {
    results = []
    toastCenter.show(ErrorPresenter.message(for: error))
}
```

移除 `.alert(item:)` 和 `ErrorWrapper`。

- [ ] **Step 5: 处理当前静默的 HTTP/API catch**

把当前可见流程里的静默 HTTP/API catch 改成：

```swift
catch {
    onError(error)
}
```

聊天发送失败需要保留失败气泡，并额外 toast：

```swift
private func markFailed(tempId: String, error: Error) {
    guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return }
    let message = ErrorPresenter.message(for: error)
    messages[index].sendState = .failed(message)
    onError(error)
    haptics.warning()
}
```

按已确认策略，`markReadIfNeeded` 的 HTTP/API 失败也 toast：

```swift
catch {
    onError(error)
}
```

- [ ] **Step 6: 添加代表性测试**

更新 `ios-app/EchoIMTests/ConversationsListViewModelTests.swift`，使用现有 stub 风格添加：

```swift
@Test
func refreshFailureCallsOnError() async {
    var received: Error?
    let vm = ConversationsListViewModel(
        repository: FailingConversationRepository(error: APIError.network(URLError(.timedOut))),
        tokenProvider: { "token" },
        onError: { received = $0 }
    )

    await vm.refresh()

    #expect(received != nil)
}
```

更新 `ios-app/EchoIMTests/ChatViewModelSendTests.swift`，使用现有 stub 风格添加：

```swift
@Test
func sendFailureCallsOnError() async {
    var received: Error?
    let vm = ChatViewModel(
        route: .peer(UserProfile(id: 2, username: "bob", displayName: nil, avatarUrl: nil)),
        currentUserId: 1,
        messageRepo: FailingMessageRepository(error: APIError.network(URLError(.notConnectedToInternet))),
        wsClient: nil,
        tokenProvider: { "token" },
        onError: { received = $0 }
    )

    await vm.sendText("hi")

    #expect(received != nil)
}
```

如果对应测试文件里已有 stub 类型，扩展现有 stub，不重复造一套。

- [ ] **Step 7: 跑聚焦 iOS 测试**

运行：

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests -only-testing:EchoIMTests/ErrorPresenterTests -only-testing:EchoIMTests/ConversationsListViewModelTests -only-testing:EchoIMTests/ChatViewModelSendTests -only-testing:EchoIMTests/LoginViewModelTests -only-testing:EchoIMTests/RegisterViewModelTests
```

预期：PASS。

- [ ] **Step 8: 构建 iOS App**

运行：

```bash
xcodebuild build -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'
```

预期：PASS。

- [ ] **Step 9: 提交**

```bash
git add ios-app/EchoIM ios-app/EchoIMTests
git commit -m "feat: show API failures as iOS toasts"
```

---

### Task 8: 端到端验证

**文件：**
- 不新增文件。

- [ ] **Step 1: 后台完整验证**

运行：

```bash
npm test --prefix server
npm run build --prefix server
npm run lint --prefix server
```

预期：PASS。

- [ ] **Step 2: iOS 聚焦验证**

运行：

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests -only-testing:EchoIMTests/ErrorPresenterTests -only-testing:EchoIMTests/ConversationsListViewModelTests -only-testing:EchoIMTests/ChatViewModelSendTests -only-testing:EchoIMTests/LoginViewModelTests -only-testing:EchoIMTests/RegisterViewModelTests
```

预期：PASS。

- [ ] **Step 3: 扫描旧后台错误结构**

运行：

```bash
rg "send\\(\\{ error: ['\\\"]" server/src server/tests
```

预期：无匹配。

- [ ] **Step 4: 手动 smoke 一个结构化 API 错误**

如果本地服务未启动，先运行：

```bash
docker compose up -d postgres
npm run migrate --prefix server
npm run dev --prefix server
```

请求未登录接口：

```bash
curl -i --max-time 5 http://localhost:3000/api/users/me
```

预期状态：

```http
HTTP/1.1 401 Unauthorized
```

预期响应体：

```json
{"error":{"code":"auth_missing","message":"Missing or invalid Authorization header"}}
```

- [ ] **Step 5: 如验证修了小问题，再补提交**

如果 Step 1-4 期间有修复：

```bash
git add server ios-app
git commit -m "test: verify structured API errors"
```

如果没有改动，跳过此步骤。

---

## 自检清单

- [ ] 后台所有错误都返回 `{ error: { code, message } }`。
- [ ] 后台实现只引用集中定义的 `ApiErrors`。
- [ ] 后台测试用字面量 `code` 锁住外部契约，而不是引用 `ApiErrors.xxx.code`。
- [ ] iOS 能从 HTTP body 解析 `ServerAPIError`。
- [ ] iOS 已知错误码走本地化文案，未知错误码 fallback 到后台英文 `message`。
- [ ] iOS HTTP/API 请求失败默认 toast。
- [ ] 后台不再残留旧 `{ error: string }` 响应结构。
