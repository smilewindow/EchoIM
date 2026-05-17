# API Error Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade EchoIM to a structured API error contract and make iOS show localized toast feedback for HTTP/API failures.

**Architecture:** Backend owns stable `snake_case` error codes and English fallback messages through a centralized `ApiErrors` registry. iOS decodes server errors, maps codes to localized copy, and routes HTTP/API failures through a shared toast presenter.

**Tech Stack:** Fastify 5, TypeScript, Vitest, Swift 6, SwiftUI Observation, Xcode project file-system synchronized groups.

---

## Reference Spec

- `docs/superpowers/specs/2026-05-17-api-error-contract-design.md`

## File Structure

Backend files:

- Create `server/src/lib/api-errors.ts`: centralized error definitions and `sendApiError`.
- Modify `server/src/app.ts`: global Fastify/AJV and 500 error conversion.
- Modify `server/src/hooks/authenticate.ts`: structured auth errors.
- Modify `server/src/routes/auth.ts`: structured auth business errors.
- Modify `server/src/routes/friend-requests.ts`: structured friend request errors.
- Modify `server/src/routes/messages.ts`: structured message errors.
- Modify `server/src/routes/conversations.ts`: structured conversation errors.
- Modify `server/src/routes/users.ts`: structured user errors.
- Modify `server/src/routes/upload.ts`: structured upload errors.
- Modify `server/tests/helpers.ts`: add `expectApiError`.
- Modify backend tests under `server/tests/*.test.ts`: assert status and literal `code`.

iOS files:

- Modify `ios-app/EchoIM/Core/Networking/APIError.swift`: decode structured server errors from HTTP bodies.
- Create `ios-app/EchoIM/Core/Networking/ErrorPresenter.swift`: map `APIError` and server codes to localized messages.
- Create `ios-app/EchoIM/Core/UI/ToastCenter.swift`: observable toast state and auto-dismiss.
- Create `ios-app/EchoIM/Core/UI/ToastOverlay.swift`: reusable SwiftUI toast overlay.
- Modify `ios-app/EchoIM/App/AppContainer.swift`: own one `ToastCenter`.
- Modify `ios-app/EchoIM/App/RootView.swift`: render global toast overlay.
- Modify visible API request call sites to show toast on HTTP/API failures:
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
- Modify `ios-app/EchoIM/Localizable.xcstrings`: add localized API error messages.
- Modify iOS tests under `ios-app/EchoIMTests`: cover decoding, localization fallback, and representative view model toast calls.

Xcode note: the project uses `PBXFileSystemSynchronizedRootGroup`, so adding Swift files under `ios-app/EchoIM/...` does not require manual `project.pbxproj` source-file entries.

---

### Task 1: Backend Error Registry

**Files:**
- Create: `server/src/lib/api-errors.ts`
- Test: `server/tests/helpers.ts`

- [ ] **Step 1: Add the centralized backend error registry**

Create `server/src/lib/api-errors.ts`:

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

- [ ] **Step 2: Add the backend test helper**

Modify `server/tests/helpers.ts` imports and append this helper:

```ts
import { expect } from 'vitest'
```

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

- [ ] **Step 3: Run focused backend type/build check**

Run:

```bash
npm run build --prefix server
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add server/src/lib/api-errors.ts server/tests/helpers.ts
git commit -m "feat: add structured API error helper"
```

---

### Task 2: Backend Global And Auth Errors

**Files:**
- Modify: `server/src/app.ts`
- Modify: `server/src/hooks/authenticate.ts`
- Modify: `server/src/routes/auth.ts`
- Modify: `server/tests/auth.test.ts`
- Modify: `server/tests/users.test.ts`

- [ ] **Step 1: Write failing tests for structured auth errors**

Modify imports in `server/tests/auth.test.ts`:

```ts
import { getApp, truncateAll, registerUser, getInviteCode, expectApiError } from './helpers.js'
```

Replace representative assertions:

```ts
expectApiError(res, 409, 'email_already_in_use')
```

```ts
expectApiError(res, 409, 'username_already_taken')
```

```ts
expectApiError(res, 401, 'invalid_credentials')
```

```ts
expectApiError(res, 400, 'invalid_request')
```

Modify imports in `server/tests/users.test.ts`:

```ts
import { getApp, truncateAll, registerUser, expectApiError } from './helpers.js'
```

For unauthenticated requests, use:

```ts
expectApiError(res, 401, 'auth_missing')
```

- [ ] **Step 2: Verify tests fail on old shape**

Run:

```bash
npm test --prefix server -- auth.test.ts users.test.ts
```

Expected: FAIL because responses still use `{ error: string }`.

- [ ] **Step 3: Convert global error handler**

Modify `server/src/app.ts`:

```ts
import { ApiErrors, sendApiError } from './lib/api-errors.js'
```

Replace `setErrorHandler` with:

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

- [ ] **Step 4: Convert auth hook**

Modify `server/src/hooks/authenticate.ts`:

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

Replace auth failures:

```ts
return sendApiError(reply, ApiErrors.authMissing)
```

```ts
return sendApiError(reply, ApiErrors.authInvalid)
```

```ts
return sendApiError(reply, ApiErrors.authInvalidPayload)
```

- [ ] **Step 5: Convert auth routes**

Modify `server/src/routes/auth.ts`:

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

Use these replacements:

```ts
return sendApiError(reply, ApiErrors.invalidInviteCode)
return sendApiError(reply, ApiErrors.usernameTooShort)
return sendApiError(reply, ApiErrors.invalidEmail)
return sendApiError(reply, ApiErrors.emailAlreadyInUse)
return sendApiError(reply, ApiErrors.usernameAlreadyTaken)
return sendApiError(reply, ApiErrors.accountAlreadyExists)
return sendApiError(reply, ApiErrors.invalidCredentials)
```

- [ ] **Step 6: Run focused backend tests**

Run:

```bash
npm test --prefix server -- auth.test.ts users.test.ts
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add server/src/app.ts server/src/hooks/authenticate.ts server/src/routes/auth.ts server/tests/auth.test.ts server/tests/users.test.ts
git commit -m "feat: structure auth API errors"
```

---

### Task 3: Backend Domain Route Errors

**Files:**
- Modify: `server/src/routes/friend-requests.ts`
- Modify: `server/src/routes/messages.ts`
- Modify: `server/src/routes/conversations.ts`
- Modify: `server/src/routes/users.ts`
- Modify: `server/src/routes/upload.ts`
- Modify: `server/tests/friends.test.ts`
- Modify: `server/tests/messages.test.ts`
- Modify: `server/tests/upload.test.ts`
- Modify: `server/tests/users.test.ts`

- [ ] **Step 1: Write failing route error assertions**

Update test imports to include `expectApiError`:

```ts
import { getApp, truncateAll, registerUser, expectApiError } from './helpers.js'
```

For tests using more helpers, preserve existing imports and append `expectApiError`.

Use these literal code assertions:

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

- [ ] **Step 2: Verify tests fail on old shape**

Run:

```bash
npm test --prefix server -- friends.test.ts messages.test.ts users.test.ts upload.test.ts
```

Expected: FAIL because route responses still use `{ error: string }`.

- [ ] **Step 3: Convert friend request route**

Modify `server/src/routes/friend-requests.ts`:

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

Replace failures:

```ts
return sendApiError(reply, ApiErrors.friendRequestSelf)
return sendApiError(reply, ApiErrors.recipientNotFound)
return sendApiError(reply, ApiErrors.friendRequestAlreadyExists)
return sendApiError(reply, ApiErrors.invalidRequest)
return sendApiError(reply, ApiErrors.friendRequestNotFound)
```

Use `friendRequestNotFound` for `Not found or already resolved`.

- [ ] **Step 4: Convert messages route**

Modify `server/src/routes/messages.ts`:

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

Replace failures:

```ts
return sendApiError(reply, ApiErrors.messageBodyRequired)
return sendApiError(reply, ApiErrors.messageMediaRequired)
return sendApiError(reply, ApiErrors.messageMediaInvalid)
return sendApiError(reply, ApiErrors.messageDimensionsInvalid)
return sendApiError(reply, ApiErrors.notFriends)
```

- [ ] **Step 5: Convert conversations route**

Modify `server/src/routes/conversations.ts`:

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

Replace failures:

```ts
return sendApiError(reply, ApiErrors.invalidConversationId)
return sendApiError(reply, ApiErrors.paginationCursorConflict)
return sendApiError(reply, ApiErrors.conversationNotFound)
return sendApiError(reply, ApiErrors.invalidLastReadMessageId)
```

Use `conversationNotFound` for membership failures to preserve resource-hiding behavior.

- [ ] **Step 6: Convert users route**

Modify `server/src/routes/users.ts`:

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

Replace failures:

```ts
return sendApiError(reply, ApiErrors.userNotFound)
return sendApiError(reply, ApiErrors.noFieldsToUpdate)
```

- [ ] **Step 7: Convert upload route**

Modify `server/src/routes/upload.ts`:

```ts
import { ApiErrors, sendApiError } from '../lib/api-errors.js'
```

Replace failures:

```ts
return sendApiError(reply, ApiErrors.fileRequired)
return sendApiError(reply, ApiErrors.invalidImageFile)
return sendApiError(reply, ApiErrors.userNotFound)
```

- [ ] **Step 8: Scan for old backend error response shape**

Run:

```bash
rg "send\\(\\{ error: '" server/src server/tests
```

Expected: no matches.

Run:

```bash
rg "send\\(\\{ error: \\\"" server/src server/tests
```

Expected: no matches.

- [ ] **Step 9: Run backend tests and build**

Run:

```bash
npm test --prefix server
npm run build --prefix server
npm run lint --prefix server
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add server/src server/tests
git commit -m "feat: structure backend business errors"
```

---

### Task 4: iOS Server Error Decoding

**Files:**
- Modify: `ios-app/EchoIM/Core/Networking/APIError.swift`
- Modify: `ios-app/EchoIM/Features/Auth/AuthRepository.swift`
- Modify: `ios-app/EchoIMTests/APIErrorTests.swift`
- Modify: `ios-app/EchoIMTests/AuthRepositoryTests.swift`

- [ ] **Step 1: Write failing APIError decoding tests**

Append to `ios-app/EchoIMTests/APIErrorTests.swift`:

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
func fallsBackWhenHTTPBodyIsLegacyOrMalformed() {
    let error = APIError.http(status: 500, body: Data("oops".utf8))

    #expect(error.serverError == nil)
}
```

- [ ] **Step 2: Verify tests fail**

Run:

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests
```

Expected: FAIL because `serverError` does not exist.

- [ ] **Step 3: Add structured server error decoding**

Modify `ios-app/EchoIM/Core/Networking/APIError.swift`:

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

- [ ] **Step 4: Update AuthRepository server message extraction**

Modify `AuthRepository.extractErrorMessage(_:)` to parse the new structured error body:

```swift
nonisolated private static func extractErrorMessage(_ body: Data) -> String {
    if let serverError = APIError.decodeServerError(from: body) {
        return serverError.message
    }

    return String(data: body, encoding: .utf8) ?? ""
}
```

Do not add support for the old `{ "error": "..." }` shape; the backend migration is intentionally a breaking API contract change.

- [ ] **Step 5: Run focused iOS tests**

Run:

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests -only-testing:EchoIMTests/AuthRepositoryTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios-app/EchoIM/Core/Networking/APIError.swift ios-app/EchoIM/Features/Auth/AuthRepository.swift ios-app/EchoIMTests/APIErrorTests.swift ios-app/EchoIMTests/AuthRepositoryTests.swift
git commit -m "feat: decode structured API errors on iOS"
```

---

### Task 5: iOS Error Presenter And Localization

**Files:**
- Create: `ios-app/EchoIM/Core/Networking/ErrorPresenter.swift`
- Modify: `ios-app/EchoIM/Localizable.xcstrings`
- Create: `ios-app/EchoIMTests/ErrorPresenterTests.swift`

- [ ] **Step 1: Write failing ErrorPresenter tests**

Create `ios-app/EchoIMTests/ErrorPresenterTests.swift`:

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

- [ ] **Step 2: Verify tests fail**

Run:

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ErrorPresenterTests
```

Expected: FAIL because `ErrorPresenter` does not exist.

- [ ] **Step 3: Implement ErrorPresenter**

Create `ios-app/EchoIM/Core/Networking/ErrorPresenter.swift`:

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

- [ ] **Step 4: Add localizations**

Modify `ios-app/EchoIM/Localizable.xcstrings` by adding keys used above. Follow the existing JSON structure. At minimum add these entries with English translations:

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

Also add any missing keys referenced by `ErrorPresenter.message(forServerCode:)`.

- [ ] **Step 5: Run focused tests**

Run:

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/ErrorPresenterTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios-app/EchoIM/Core/Networking/ErrorPresenter.swift ios-app/EchoIM/Localizable.xcstrings ios-app/EchoIMTests/ErrorPresenterTests.swift
git commit -m "feat: localize iOS API errors"
```

---

### Task 6: iOS Global Toast Surface

**Files:**
- Create: `ios-app/EchoIM/Core/UI/ToastCenter.swift`
- Create: `ios-app/EchoIM/Core/UI/ToastOverlay.swift`
- Modify: `ios-app/EchoIM/App/AppContainer.swift`
- Modify: `ios-app/EchoIM/App/RootView.swift`

- [ ] **Step 1: Create ToastCenter**

Create `ios-app/EchoIM/Core/UI/ToastCenter.swift`:

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

- [ ] **Step 2: Create ToastOverlay**

Create `ios-app/EchoIM/Core/UI/ToastOverlay.swift`:

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

- [ ] **Step 3: Add ToastCenter to AppContainer**

Modify `ios-app/EchoIM/App/AppContainer.swift`:

```swift
let toastCenter: ToastCenter
```

Initialize it:

```swift
self.toastCenter = ToastCenter()
```

Show auth expiry through the same center:

```swift
func showErrorToast(for error: Error) {
    toastCenter.show(ErrorPresenter.message(for: error))
}

func showToast(_ message: String) {
    toastCenter.show(message)
}
```

In `handleUnauthorized()`, after `sessionExpiredNoticeID = UUID()` add:

```swift
toastCenter.show(String(localized: "登录状态已失效，请重新登录"))
```

- [ ] **Step 4: Replace RootView private session toast overlay**

Modify `ios-app/EchoIM/App/RootView.swift`:

Remove:

```swift
@State private var sessionExpiredToastVisible = false
@State private var toastDismissTask: Task<Void, Never>?
```

Remove the `.onChange(of: container.sessionExpiredNoticeID)` block that manages private toast visibility.

Replace the overlay with:

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

Remove the private `sessionExpiredToast(_:)` method.

- [ ] **Step 5: Build iOS app**

Run:

```bash
xcodebuild build -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add ios-app/EchoIM/Core/UI/ToastCenter.swift ios-app/EchoIM/Core/UI/ToastOverlay.swift ios-app/EchoIM/App/AppContainer.swift ios-app/EchoIM/App/RootView.swift
git commit -m "feat: add global iOS toast surface"
```

---

### Task 7: iOS Wire HTTP/API Failures To Toast

**Files:**
- Modify: feature view models and views listed in File Structure.
- Test: representative tests under `ios-app/EchoIMTests`.

- [ ] **Step 1: Add a shared error callback pattern to view models**

For each view model that performs HTTP/API requests, add:

```swift
private let onError: @MainActor (Error) -> Void
```

Add initializer parameter with a default no-op:

```swift
onError: @escaping @MainActor (Error) -> Void = { _ in }
```

Assign it:

```swift
self.onError = onError
```

When a caught error should be surfaced, call:

```swift
onError(error)
```

Apply this to:

- `ConversationsListViewModel`
- `ContactsViewModel`
- `ChatViewModel`
- `ProfileEditViewModel`

- [ ] **Step 2: Preserve existing auth view model string state while using ErrorPresenter**

Modify `LoginViewModel.toastMessage(for:)` and `RegisterViewModel` error paths so known `AuthError` mappings remain localized. For unexpected errors, use:

```swift
toast = ErrorPresenter.message(for: error)
```

Do not remove existing login/register tests in this task; they protect current auth UX.

- [ ] **Step 3: Pass AppContainer toast closures from views**

When constructing feature view models, pass:

```swift
onError: { [toastCenter = container.toastCenter] error in
    toastCenter.show(ErrorPresenter.message(for: error))
}
```

For views that do not receive `container`, pass `toastCenter` down explicitly from `MainTabView`.

Update initializers:

```swift
ConversationsListView(..., toastCenter: container.toastCenter, ...)
ContactsView(..., toastCenter: container.toastCenter, ...)
ChatView(..., toastCenter: container.toastCenter, ...)
ProfileEditView(..., toastCenter: container.toastCenter, ...)
```

- [ ] **Step 4: Replace UserSearchSheetView local alert with toast**

Remove:

```swift
@State private var errorToast: String?
```

Add:

```swift
let toastCenter: ToastCenter
```

On send failure:

```swift
if case .failure(let error) = result {
    toastCenter.show(ErrorPresenter.message(for: error))
}
```

On search failure:

```swift
} catch {
    results = []
    toastCenter.show(ErrorPresenter.message(for: error))
}
```

Remove the `.alert(item:)` block and `ErrorWrapper`.

- [ ] **Step 5: Surface currently swallowed HTTP/API catch blocks**

Replace silent HTTP/API catches with `onError(error)` in visible flows:

```swift
catch {
    onError(error)
}
```

For chat send failure, keep bubble failed state and add toast:

```swift
private func markFailed(tempId: String, error: Error) {
    guard let index = messages.firstIndex(where: { $0.localId == tempId }) else { return }
    let message = ErrorPresenter.message(for: error)
    messages[index].sendState = .failed(message)
    onError(error)
    haptics.warning()
}
```

For `markReadIfNeeded`, also toast on catch because it is an HTTP/API failure under the simplified policy:

```swift
catch {
    onError(error)
}
```

- [ ] **Step 6: Add representative tests**

Add or update tests to cover one request failure per major area:

`ios-app/EchoIMTests/ConversationsListViewModelTests.swift`:

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

`ios-app/EchoIMTests/ChatViewModelSendTests.swift`:

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

Use existing test stub styles in those files; if a stub type already exists, extend it instead of creating a duplicate.

- [ ] **Step 7: Run focused iOS tests**

Run:

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests -only-testing:EchoIMTests/ErrorPresenterTests -only-testing:EchoIMTests/ConversationsListViewModelTests -only-testing:EchoIMTests/ChatViewModelSendTests -only-testing:EchoIMTests/LoginViewModelTests -only-testing:EchoIMTests/RegisterViewModelTests
```

Expected: PASS.

- [ ] **Step 8: Build iOS app**

Run:

```bash
xcodebuild build -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add ios-app/EchoIM ios-app/EchoIMTests
git commit -m "feat: show API failures as iOS toasts"
```

---

### Task 8: End-To-End Verification

**Files:**
- No new files.

- [ ] **Step 1: Run full backend verification**

Run:

```bash
npm test --prefix server
npm run build --prefix server
npm run lint --prefix server
```

Expected: PASS.

- [ ] **Step 2: Run targeted iOS verification**

Run:

```bash
xcodebuild test -project ios-app/EchoIM.xcodeproj -scheme EchoIM -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' -only-testing:EchoIMTests/APIErrorTests -only-testing:EchoIMTests/ErrorPresenterTests -only-testing:EchoIMTests/ConversationsListViewModelTests -only-testing:EchoIMTests/ChatViewModelSendTests -only-testing:EchoIMTests/LoginViewModelTests -only-testing:EchoIMTests/RegisterViewModelTests
```

Expected: PASS.

- [ ] **Step 3: Scan for old backend shape**

Run:

```bash
rg "send\\(\\{ error: ['\\\"]" server/src server/tests
```

Expected: no matches.

- [ ] **Step 4: Smoke-test one structured API error manually**

Start services if needed:

```bash
docker compose up -d postgres
npm run migrate --prefix server
npm run dev --prefix server
```

Make a request without auth:

```bash
curl -i --max-time 5 http://localhost:3000/api/users/me
```

Expected response:

```http
HTTP/1.1 401 Unauthorized
```

```json
{"error":{"code":"auth_missing","message":"Missing or invalid Authorization header"}}
```

- [ ] **Step 5: Final commit if verification required small fixes**

```bash
git add server ios-app
git commit -m "test: verify structured API errors"
```

Skip this commit if Step 1-4 required no changes.

---

## Self-Review Checklist

- [ ] Backend exposes only `{ error: { code, message } }` for errors.
- [ ] Tests lock literal backend `code` strings, not `ApiErrors.xxx.code`.
- [ ] Backend implementation references centralized `ApiErrors`.
- [ ] iOS maps known codes through localized strings and falls back to server `message`.
- [ ] iOS HTTP/API failures are routed to toast.
- [ ] Local cache write failures are not part of this protocol.
- [ ] No legacy backend `{ error: string }` shape remains.
