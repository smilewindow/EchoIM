# API Error Contract Design

## 背景

EchoIM 后台目前大多数业务错误使用正确的 HTTP 4xx/5xx 状态码，但响应体仍是松散的
`{ "error": "message" }` 字符串结构。iOS 端只能在少数模块里解析这些字符串，其它地方会展示
`String(describing: error)` 或静默忽略，导致用户无法稳定理解网络/API 失败原因。

本设计把后台错误响应升级为稳定协议，让客户端用错误码做国际化展示，并保留英文 message 作为兜底。

## 目标

- 后台所有错误响应统一为 `{ error: { code, message } }`。
- `code` 是稳定、可测试、可被客户端本地化映射的协议字段。
- `message` 是英文 fallback 和调试可读信息，不作为最终用户文案的唯一来源。
- iOS 端后续通过 `code` 映射 `Localizable.xcstrings`，支持中英文 toast。
- 一次性替换后台所有旧格式，不保留旧 `{ error: string }` 兼容层。

## 非目标

- 不在这次加入 `field`、`details`、多错误数组或字段级表单错误协议。
- 不在这次定义数字错误码。
- 不在这次重做好友申请的产品规则，例如 declined 后是否允许重新申请。
- 不把后台 message 改成中文，也不让后台承担客户端国际化职责。
- 不改变成功响应结构。

## 响应结构

所有错误响应都使用以下结构：

```json
{
  "error": {
    "code": "friend_request_already_exists",
    "message": "Friend request already exists"
  }
}
```

字段约定：

- `error.code`：必填。文本 `snake_case`，由后台集中定义，客户端依赖它做分支和本地化。
- `error.message`：必填。英文 fallback，便于日志、调试和未映射客户端兜底展示。

HTTP 状态码继续表达错误类别：

- `400`：请求格式、参数或业务输入非法。
- `401`：未认证、token 无效或 token payload 非法。
- `403`：认证通过但不允许执行该业务动作。
- `404`：资源不存在，或为了隐藏权限关系而不暴露资源存在性。
- `409`：业务冲突，例如重复注册、重复好友申请。
- `500`：服务端内部错误，响应体不泄露内部异常。

## 错误定义集中化

后台新增 `server/src/lib/api-errors.ts`，集中维护错误定义和发送 helper。

设计形态：

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

路由不再直接写 `{ error: "..." }`，而是引用集中定义：

```ts
return sendApiError(reply, ApiErrors.friendRequestAlreadyExists)
```

## 全局错误处理

`server/src/app.ts` 的 Fastify error handler 负责兜底转换：

- Fastify/AJV validation error 统一返回 `invalid_request`。
- 其它 4xx Fastify 错误返回通用 `invalid_request` 或后续明确的集中错误定义。
- 未捕获 5xx 返回 `internal_error`，只在服务端日志记录真实异常。

Fastify/AJV 错误不把原始技术文案透传给客户端，避免出现 `body must have required property` 这类用户不可读信息。

## 鉴权错误

`server/src/hooks/authenticate.ts` 细分鉴权错误，便于后台日志和客户端调试：

- `auth_missing`：缺少 `Authorization` header，或不是 `Bearer` 格式。
- `auth_invalid`：token 过期、签名错误或无法验证。
- `auth_invalid_payload`：token 结构不是后台期望的 `{ id: number }`。

这些错误都返回 `401`。iOS 可以统一映射为“登录状态已失效，请重新登录”。

## 业务错误码策略

错误码使用文本 `snake_case`。命名遵循“领域 + 原因”，不使用数字段。

首批需要覆盖的错误包括：

```ts
invalid_request
internal_error
auth_missing
auth_invalid
auth_invalid_payload
invalid_invite_code
username_too_short
invalid_email
email_already_in_use
username_already_taken
account_already_exists
invalid_credentials
user_not_found
no_fields_to_update
friend_request_self
recipient_not_found
friend_request_already_exists
friend_request_not_found
message_body_required
message_media_required
message_media_invalid
message_dimensions_invalid
not_friends
invalid_conversation_id
pagination_cursor_conflict
conversation_not_found
invalid_last_read_message_id
file_required
invalid_image_file
```

好友申请冲突暂时保持一个通用错误码：

```ts
friend_request_already_exists
```

它覆盖正向重复、反向已存在、已接受关系或历史记录造成的唯一约束冲突。更细分的产品语义后续单独设计。

## 权限隐藏策略

对于“资源存在但当前用户不属于该资源”的情况，继续使用 `404`，避免向客户端暴露资源存在性。

例如会话消息查询中，用户不是会话成员时返回：

```json
{
  "error": {
    "code": "conversation_not_found",
    "message": "Conversation not found"
  }
}
```

不返回 `not_a_member_of_conversation`。

## iOS 消费方式

iOS 后续需要把 `APIError.http(status:body:)` 解析为结构化错误：

```swift
struct APIErrorResponse: Decodable, Equatable {
    let error: ServerAPIError
}

struct ServerAPIError: Decodable, Equatable {
    let code: String
    let message: String
}
```

展示规则：

1. 优先使用 `code` 查 `Localizable.xcstrings`。
2. 找不到本地化映射时，fallback 到后台 `message`。
3. 网络断开、超时、解码失败、无效响应等非业务错误继续由 iOS 本地生成文案。
4. HTTP/API 请求失败默认展示 toast，包括页面进入、刷新、用户动作和当前可见页面的自动补拉。
5. 本地缓存写入、纯本地状态处理等非 HTTP/API 错误不属于本协议范围。

## 测试要求

后台测试需要从只断言状态码，升级为同时断言错误结构：

```ts
expect(res.statusCode).toBe(409)
expect(res.json()).toEqual({
  error: {
    code: 'friend_request_already_exists',
    message: 'Friend request already exists',
  },
})
```

需要覆盖：

- Auth 注册/登录错误。
- 鉴权 hook 错误。
- 好友申请错误。
- 消息发送错误。
- 会话查询/已读错误。
- 用户资料错误。
- 上传错误。
- Fastify/AJV schema validation 错误统一为 `invalid_request`。
- 未捕获服务端错误统一为 `internal_error`。

## 发布顺序

这是 breaking change，不应单独只发后台。

推荐执行顺序：

1. 后台实现新错误协议并更新 server tests。
2. iOS 实现新结构解析、错误码本地化和 toast 展示。
3. 后台和 iOS 同一发布批次合并。

## 验收标准

- 后台代码中不再出现 `send({ error: '...' })` 旧格式。
- 所有后台错误响应都符合 `{ error: { code, message } }`。
- `npm test --prefix server` 通过。
- iOS 能从任意 HTTP 4xx/5xx 业务错误中读取 `code` 和 `message`。
- iOS 对已映射错误码展示本地化 toast，对未映射错误码 fallback 后台英文 message。
