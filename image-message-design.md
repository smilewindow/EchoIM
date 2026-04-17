# 图片消息功能设计文档

**日期：** 2026-04-13  
**状态：** 已确认，已实施

---

## 概述

在现有文本消息基础上，新增图片消息发送能力。支持乐观 UI 预览、点击放大查看原图。暂不支持图注（caption）、缩略图尺寸优化（按需 resize）等功能，可后续迭代。

**图片格式限制：** 仅支持静态图片展示；GIF 上传后会被转为静态 JPEG，透明背景填充为白色。这与现有头像上传行为一致。

---

## 核心决策

| 决策点 | 结论 |
|---|---|
| 发送方式 | 先上传再发消息 + 乐观 UI（blob URL 预览） |
| 区分消息类型 | 新增 `message_type` + `media_url` 两列 |
| body 字段 | 改为 NULLABLE，图片消息可不传 |
| 图注（caption） | 暂不支持 |
| 客户端压缩上限 | 长边 1600px，目标 ≤ 2MB（与服务端上限一致，避免冗余压缩） |
| 服务端处理 | sharp 长边 ≤ 1600px，JPEG quality 80，透明背景填白 |
| 气泡内缩略图 | 直接渲染原图，**保留原宽高比**，CSS 限制 `max-width: 300px; max-height: 300px`（不 cover 裁切） |
| 点击查看 | Lightbox 展示原图 |
| 会话列表预览 | 图片消息显示 `[图片]`（i18n） |
| 响应式尺寸优化 | 暂不做，后续可加 srcset |

---

## 数据库变更

新增迁移文件 `007_message_media.sql`：

```sql
-- body 改为可空（原 NOT NULL）
ALTER TABLE messages ALTER COLUMN body DROP NOT NULL;

-- 新增消息类型和媒体 URL
ALTER TABLE messages
  ADD COLUMN message_type VARCHAR(20) NOT NULL DEFAULT 'text',
  ADD COLUMN media_url    TEXT;

-- 内容完整性约束：显式枚举 message_type，并按类型校验必填内容字段。
-- 显式 IN 子句的作用是让未来新增类型时 CHECK 会立刻失败、提醒开发者同步约束，
-- 而不是被两个 OR 分支"隐式拒绝"。
ALTER TABLE messages ADD CONSTRAINT messages_content_check
  CHECK (
    message_type IN ('text', 'image') AND (
      (message_type = 'text'  AND body IS NOT NULL AND body <> '') OR
      (message_type = 'image' AND media_url IS NOT NULL)
    )
  );
```

---

## 服务端变更

### 1. 新增上传接口 `POST /api/upload/message-image`

**路由注册位置：** 在现有 `server/src/routes/upload.ts` 内**追加 handler**，复用该文件顶部已经注册的 `@fastify/multipart` 插件。**不要**新建独立文件，否则会二次注册同一 plugin 触发 Fastify 报错。同时把原来写死在文件顶部的 `UPLOADS_DIR / OUTPUT_SIZE / OUTPUT_QUALITY` 常量重构成按路由区分的配置（avatar vs message-image）。

- **认证：** 需要 JWT（`authenticate` hook，已由现有 `preHandler` 提供）
- **输入：** multipart/form-data，字段名 `file`，最大 10MB
- **处理：** sharp 等比缩放，最长边 ≤ 1600px，JPEG quality 80，透明背景 `flatten` 填白（与 avatar 一致）
- **存储：** `uploads/messages/{userId}-{timestamp}.jpg`（`Date.now()` 毫秒时间戳）
- **返回：** `{ media_url: "/uploads/messages/{userId}-{timestamp}.jpg" }`
- **错误：** 无文件 400，非图片 400，超限由 multipart 插件返回 413

### 2. 修改 `POST /messages`

Schema 变更：
- `body`：由必填改为可选（去掉 `required`，去掉 `minLength`）
- 新增可选字段 `message_type`（默认 `'text'`）
- 新增可选字段 `media_url`

服务端校验逻辑：
```
if message_type === 'text':  body 必须为非空字符串
if message_type === 'image': media_url 必须存在，且通过归属校验（见下）
```

**media_url 归属校验：** `media_url` 必须匹配当前登录用户的正则模式：

```
^/uploads/messages/${sender_id}-\d{10,16}\.jpg$
```

- `sender_id` 来自 JWT，不是用户输入，不需要额外转义
- 时间戳限制 10–16 位，覆盖 `Date.now()` 的合理取值范围（2001 年到遥远未来），同时拒绝 `0`、`1`、超长数字等探测性构造

拒绝任何不符合此模式的值（包含外部 URL、其他用户的文件路径、uploads/avatars/ 等路径），返回 400。此规则防止越权引用他人文件和跟踪像素注入。

INSERT 语句更新为携带 `message_type` 和 `media_url`。

### 3. 静态文件服务

`uploads/messages/` 目录通过现有 `static.ts` 插件对外暴露（与 `uploads/avatars/` 同一机制）。

### 4. 会话列表 API (`GET /conversations`)

`conversations.ts` 中的 LATERAL 子查询需要补选 `message_type`：

```sql
LEFT JOIN LATERAL (
  SELECT body, sender_id, created_at, message_type
  FROM messages WHERE conversation_id = c.id ORDER BY id DESC LIMIT 1
) last_msg ON true
```

并在 SELECT 列表中新增 `last_msg.message_type AS last_message_type`，返回给前端用于会话列表预览文案判断。

---

## 客户端变更

### 1. 压缩工具参数化（`lib/image.ts`）

现有 `compressImage` 硬编码 `MAX_DIMENSION=800 / TARGET_SIZE_BYTES=500KB`，是为头像设计的。直接复用到聊天图会把图先压到 800px，服务端 1600px 的上限失效。重构为接受可选参数：

```ts
export interface CompressOptions {
  maxDimension?: number      // 默认 800
  targetSizeBytes?: number   // 默认 500 * 1024
  minDimension?: number      // 默认 200
  minQuality?: number        // 默认 0.4
}

export async function compressImage(file: File, opts?: CompressOptions): Promise<Blob>
```

调用方：
- 头像（`ProfileEditPage`）：不传 opts，沿用原默认值，行为不变
- 聊天图（`sendImageMessage`）：传 `{ maxDimension: 1600, targetSizeBytes: 2 * 1024 * 1024, minDimension: 400 }`

`validateImageFile` 继续沿用现有 10MB 上限，不需要改。

### 2. 类型与 store 扩展（`stores/chat.ts`）

**Message 接口：**

```ts
export interface Message {
  id: number | string
  conversation_id: number
  sender_id: number
  body: string | null          // 原 string，改为可空
  created_at: string
  client_temp_id?: string
  message_type?: 'text' | 'image'
  media_url?: string | null
  _status?: 'pending' | 'failed'
  _tempId?: string
  _localMediaUrl?: string      // 乐观 UI 期间的本地 blob URL
  _localBlob?: Blob            // 压缩后的 blob，用于上传失败时重试，不落库
  _uploadStage?: 'uploading' | 'sending'  // 区分当前失败发生在哪个阶段
}
```

**Conversation 接口新增：**

```ts
last_message_type?: string    // 由 GET /conversations 返回
```

**store 新增方法：**

```ts
sendImageMessage: (recipientId: number, file: File) => Promise<void>
retryMessage: (tempId: string) => void  // 统一入口，store 内部按 message_type 分支
```

`retryMessage` 从 `(tempId, recipientId, body)` 收口为 `(tempId)`，视图层无需知道消息类型；store 内部根据消息的 `message_type` 和 `_uploadStage` 决定从哪个阶段重试。

### 3. 图片发送状态机（`stores/chat.ts` — `sendImageMessage`）

发送逻辑全部下沉到 store，ChatView 只负责触发文件选择并调用 `sendImageMessage`。

**状态流转：**

```
选图成功
  → 压缩（compressImage）
  → 插入乐观气泡（_status: 'pending', _uploadStage: 'uploading', _localMediaUrl: objectURL, _localBlob: blob）
  → POST /api/upload/message-image
      失败 → _status: 'failed'，_uploadStage: 'uploading'（重试从上传开始）
      成功 → 更新气泡 _uploadStage: 'sending'，记录 media_url
  → POST /api/messages { recipient_id, message_type: 'image', media_url, client_temp_id }
      失败 → _status: 'failed'，_uploadStage: 'sending'，保留已有 media_url（重试跳过上传）
      成功 → 替换乐观气泡为服务端消息；revokeObjectURL(_localMediaUrl)；清除 _localBlob
```

乐观替换、WS/REST 去重、新建会话切换等逻辑复用现有 `replaceOrAppendMessage` 和 `isSameChatContext`。

**会话列表热更新**（`sendImageMessage` 成功回调 和 `handleIncomingMessage`）需同步维护 `last_message_type`，与现有 `last_message_body` 更新位置一致：

```ts
// 发送成功回调（原 sendMessage 处已有类似逻辑）
conversations.map(c => c.id === convId ? {
  ...c,
  last_message_body: result.body,
  last_message_type: result.message_type,
  last_message_sender_id: result.sender_id,
  last_message_at: result.created_at,
} : c)

// handleIncomingMessage 同理
```

**Retry 幂等保护：** `retryMessage(tempId)` 被调用后，立即把该气泡状态切回 `_status: 'pending'`。MessageBubble 只在 `_status === 'failed'` 时渲染 retry 按钮，因此切回 pending 后按钮立即消失，用户无法连点触发并发请求。store 内部通过这个状态翻转天然获得幂等性，无需额外 flag。

### 4. ChatView 输入区

在发送按钮左侧新增图片按钮（`ImageIcon`），触发隐藏的 `<input type="file" accept="image/*">`。

校验（`validateImageFile`）在 ChatView 层做，校验失败直接 toast 提示，不进入 store。校验通过后调用 `sendImageMessage(recipientId, file)`。

### 5. MessageBubble 渲染

图片消息优先显示 `_localMediaUrl`（乐观预览），确认后展示 `media_url`：

```tsx
{msg.message_type === 'image' ? (
  <img
    src={msg._localMediaUrl ?? msg.media_url ?? ''}
    className="echo-bubble-image"
    onClick={() => {
      const url = msg.media_url ?? msg._localMediaUrl
      if (url) openLightbox(url)
    }}
  />
) : (
  <p className="echo-bubble-body">{msg.body}</p>
)}
```

CSS 约束（气泡内小图，**保留原宽高比**，不做 cover 裁切）：
```css
.echo-bubble-image {
  max-width: 300px;
  max-height: 300px;
  width: auto;
  height: auto;
  border-radius: 8px;
  cursor: pointer;
  display: block;
}
```

说明：不使用 `width: 100%` 和 `object-fit: cover`，避免竖图被强制拉伸到正方形 + 裁切内容。代价是气泡宽度随图片比例变化，长图/竖图看起来不对齐——这是可以接受的 trade-off（类 iMessage/WeChat 行为）。

### 6. Lightbox 组件

独立的轻量组件，点击气泡内图片触发，展示原图全屏预览：
- 背景半透明遮罩，点击遮罩关闭
- 键盘 `Esc` 关闭
- 图片居中显示，`max-width: 90vw; max-height: 90vh`
- 无需第三方库，React portal 实现（挂到 `document.body`）

**可访问性 / 细节：**
- 根元素 `role="dialog" aria-modal="true" aria-label={t('chat.imagePreview')}`
- 打开时：
  - `document.body.style.overflow = 'hidden'`（防止背景滚动）
  - 记录 `document.activeElement` 作为触发元素引用
  - 把焦点移到关闭按钮（或对话框根节点 `tabIndex={-1}`）
- 关闭时：
  - 恢复 `document.body.style.overflow`
  - 把焦点还回打开时记录的触发元素
- 焦点 trap：Tab/Shift+Tab 在对话框内循环（关闭按钮 + 图片链接下载等）；对于仅单按钮的 MVP 实现可以简化为"Tab 始终停在关闭按钮"
- 事件监听器挂在 `document` 上，组件卸载时清理

### 7. ConversationList 预览文案

```tsx
const preview = conv.last_message_body
  ?? (conv.last_message_type === 'image' ? t('chat.imageMessage') : t('conversations.noMessages'))
```

i18n key 新增：
- `chat.imageMessage`：`[图片]`（中文）/ `[Image]`（英文）
- `chat.imagePreview`：`图片预览`（中文）/ `Image preview`（英文） — Lightbox 的 aria-label

---

## 错误处理

| 场景 | 处理方式 |
|---|---|
| 文件类型不支持 | toast 提示，不插入气泡 |
| 文件超过 10MB | toast 提示，不插入气泡 |
| 上传失败（网络/服务端） | 气泡标记 failed（_uploadStage: 'uploading'），重试从上传开始 |
| 发消息失败（上传成功但 POST 失败） | 气泡标记 failed（_uploadStage: 'sending'），重试跳过上传直接 POST |
| media_url 不符合归属校验 | 服务端返回 400，气泡标记 failed |

---

## 测试计划

### 服务端（Vitest，`server/tests/`）

**`upload.test.ts`（在现有 avatar 测试旁新增 describe 块）：**
- 未登录 → 401
- 无文件字段（空 multipart） → 400
- 非图片 buffer（随机二进制） → 400
- 超过 10MB → 413（由 multipart 插件返回）
- 成功上传返回 `media_url`，且字符串匹配归属 regex
- 上传成功后文件真实写入磁盘，后续测试可清理

**`messages.test.ts`（新增 schema 分支用例）：**
- text 消息不传 body → 400
- text 消息传空 body → 400（schema `minLength: 1`）
- image 消息不传 `media_url` → 400
- image 消息带非法 `media_url`：
  - 他人文件（`/uploads/messages/{otherUserId}-...`） → 400
  - avatars 路径（`/uploads/avatars/...`） → 400
  - 外部 URL（`https://evil.com/x.jpg`） → 400
  - 格式不匹配（`.png` 结尾、时间戳 1 位） → 400
- 正常 image 消息 → 201，返回体包含 `message_type: 'image'` 和 `media_url`
- 图片消息的 WS 广播 payload 同样携带 `message_type` / `media_url`

**`conversations.test.ts`（新增断言）：**
- 会话列表 `last_message_type` 字段随最新消息类型正确变化（text/image 切换）

**DB 迁移 / 约束层（可在 `messages.test.ts` 或新增 `migrations.test.ts`）：**
- 直接 INSERT `message_type='text'` 且 body 为空 → CHECK 拒绝
- 直接 INSERT `message_type='image'` 且 media_url 为 NULL → CHECK 拒绝
- 直接 INSERT `message_type='video'` → CHECK 拒绝（验证显式枚举生效）

### 客户端（手工回归）

覆盖关键路径，和 `tasks.md` 里阶段 11 的手工测试体例一致：

- 选图成功路径：文件选择 → 乐观气泡出现（本地 blob 预览）→ 上传完成 → 替换为服务端消息，`_localMediaUrl` 被 `URL.revokeObjectURL`
- 上传阶段失败：关掉服务端 / 断网 → 气泡 `_status: 'failed' _uploadStage: 'uploading'`，retry 从上传开始
- 消息阶段失败：上传成功但 POST /messages 失败 → 气泡 `_uploadStage: 'sending'`，retry 跳过上传直接 POST
- retry 幂等：点击 retry 后按钮立即消失（因为状态切回 pending），快速连点不会并发请求
- 接收方：对端收到图片消息后正确渲染，点击能打开 Lightbox
- 会话列表：最近一条是图片时预览显示 `[图片]` / `[Image]`
- Lightbox：Esc 关闭；点击遮罩关闭；关闭后焦点回到原气泡图片；打开时背景不可滚动
- 校验失败：选非图片文件 / 超过 10MB 文件 → toast 提示，不插入气泡
- i18n：中英文切换下所有文案正确显示

### 自动化补充（可选）

客户端目前未接入测试运行器（见 `CLAUDE.md`），不要求新增 e2e；手工回归通过即可。

## 已知限制

**孤儿文件：** 图片上传成功后，若 POST /messages 失败且用户不重试（关闭页面、切走），`uploads/messages/` 下会残留未被任何消息引用的文件。对作品集项目规模属可接受的技术债，后续可通过定时清理脚本（对比 messages 表中的 media_url）处理。

---

## 暂不实现（后续迭代）

- 图注（caption）支持
- 缩略图 / srcset 按屏幕尺寸优化
- 多图发送
- 视频、音频、文件类型扩展
