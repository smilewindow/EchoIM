CREATE TYPE friend_request_status AS ENUM ('pending', 'accepted', 'declined');

CREATE TABLE IF NOT EXISTS friend_requests (
  id           SERIAL PRIMARY KEY,
  sender_id    INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_id INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status       friend_request_status NOT NULL DEFAULT 'pending',
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT no_self_request CHECK (sender_id <> recipient_id),
  CONSTRAINT unique_request UNIQUE (sender_id, recipient_id)
);

CREATE UNIQUE INDEX unique_friend_pair ON friend_requests (LEAST(sender_id, recipient_id), GREATEST(sender_id, recipient_id));
