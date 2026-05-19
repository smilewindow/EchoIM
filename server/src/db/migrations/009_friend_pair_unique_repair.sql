-- 修复已执行过 002 但缺少 unique_friend_pair 的数据库。
-- 当前产品语义：一对用户只保留一条关系/申请记录；accepted 优先于 pending/declined。
WITH ranked_friend_requests AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id)
      ORDER BY
        CASE status
          WHEN 'accepted' THEN 1
          WHEN 'pending' THEN 2
          WHEN 'declined' THEN 3
        END,
        updated_at DESC,
        id ASC
    ) AS rank_in_pair
  FROM friend_requests
)
DELETE FROM friend_requests fr
USING ranked_friend_requests ranked
WHERE fr.id = ranked.id
  AND ranked.rank_in_pair > 1;

ALTER TABLE friend_requests DROP CONSTRAINT IF EXISTS unique_request;

DROP INDEX IF EXISTS unique_request;

CREATE UNIQUE INDEX IF NOT EXISTS unique_friend_pair
ON friend_requests (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id));
