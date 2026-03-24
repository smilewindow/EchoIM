ALTER TABLE conversation_members
  DROP COLUMN IF EXISTS last_read_at;

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS last_read_message_id INTEGER;
