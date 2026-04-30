-- 图片消息携带的真实像素宽高。客户端首屏用它预留正确占位比例，避免 LazyImage
-- 异步落定后重排 ScrollView 内容、把已对齐的"滚到底部"挤偏。
ALTER TABLE messages
  ADD COLUMN media_width  INTEGER,
  ADD COLUMN media_height INTEGER;

-- 历史 image 行没有尺寸（NULL），客户端按 4:3 占位兜底；新发送的 image 应同时写入。
-- 故意不强加 NOT NULL，以便老数据仍可读出且不阻塞 migration。
