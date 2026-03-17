CREATE TABLE IF NOT EXISTS messages (
  id              SERIAL      PRIMARY KEY,
  conversation_id INTEGER     NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id       INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body            TEXT        NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  FOREIGN KEY (conversation_id, sender_id) REFERENCES conversation_members(conversation_id, user_id)
);
