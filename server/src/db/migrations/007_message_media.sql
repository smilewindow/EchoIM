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
