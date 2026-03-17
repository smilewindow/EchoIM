CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON messages (conversation_id, created_at);

CREATE INDEX IF NOT EXISTS idx_friend_requests_recipient_status
  ON friend_requests (recipient_id, status);
