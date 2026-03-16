# EchoIM — Product Requirements Document

**Version:** 1.1 (MVP — post-interview)
**Date:** 2026-03-16

---

## 1. Overview

EchoIM is a real-time, browser-based instant messaging application built as a portfolio piece. The MVP delivers a complete 1-on-1 chat experience: register, send/accept friend requests, and exchange messages in real time across multiple devices.

---

## 2. Goals

- Deliver a working real-time chat experience with minimal scope.
- Produce a polished, deployable portfolio project demonstrating full-stack engineering.
- Ship a stable, cloud-deployable product end-to-end.

---

## 3. Out of Scope (MVP)

- Group chats / channels
- Voice or video calls
- File / image sharing (avatars use URL only)
- Message reactions, threads, or replies
- Push notifications (Web Push / mobile)
- Message search
- User blocking / reporting
- Admin dashboard
- Avatar file upload (URL input only)

---

## 4. User Stories

### Authentication
| ID | Story |
|----|-------|
| A1 | As a new user, I can register with a username, email, and password. |
| A2 | As a returning user, I can log in with my email and password. |
| A3 | As a logged-in user, I can log out. |

### Friend Requests
| ID | Story |
|----|-------|
| F1 | As a user, I can search for other registered users by username. |
| F2 | As a user, I can send a friend request to another user. |
| F3 | As a user, I can accept or decline an incoming friend request. |
| F4 | As a user, I can view my friends list (accepted contacts). |

### Messaging
| ID | Story |
|----|-------|
| M1 | As a user, I can open a 1-on-1 conversation with a friend. |
| M2 | As a user, I can send a text message using Enter (Shift+Enter for newline). |
| M3 | As a user, I can receive messages in real time on all my open tabs/devices. |
| M4 | As a user, I can scroll through paginated message history. |
| M5 | As a user, I can see a list of my recent conversations with unread counts. |
| M6 | As a user, I can see when my friend is typing. |
| M7 | As a user, I can see when a message fails to send and retry it. |

### Presence
| ID | Story |
|----|-------|
| PR1 | As a user, I can see whether my friends are currently online. |

### Profile
| ID | Story |
|----|-------|
| P1 | As a user, I can set or update my display name and avatar URL. |

---

## 5. Functional Requirements

### 5.1 Authentication
- Register: unique email + username, hashed password (bcrypt cost ≥ 12), returns a JWT.
- Login: email + password, returns a JWT.
- JWT stored in `localStorage` on the client. Expiry: 7 days.
- All protected REST routes require `Authorization: Bearer <token>`.
- WebSocket auth: token passed as query param `?token=<jwt>` (acceptable tradeoff for a portfolio project; noted as a known logging risk).

### 5.2 Friend Requests
- Contacts are **mutual**: user A sends a request; user B must accept before either can message the other.
- Users cannot message someone who is not an accepted friend.
- `friend_requests` table tracks pending/accepted/declined state.
- On acceptance, both users appear in each other's friends list.

### 5.3 Conversations & Messages
- A conversation is created automatically when two friends exchange their first message.
- Message fields: `id`, `conversation_id`, `sender_id`, `body`, `created_at`.
- Messages are delivered in real time via WebSocket to **all active sessions** of the recipient (multi-device fan-out).
- On reconnect, the client fetches messages since its last received `created_at`.
- Conversation list is sorted by most recent message descending, with server-tracked unread counts.
- Message history is paginated (cursor-based, 50 messages per page).
- If a message fails to send, the UI shows a "failed" indicator with a manual retry button.

### 5.4 Real-Time (WebSocket)
- Server maintains one or more WebSocket connections per authenticated user (multi-device).
- All sessions for a user receive the same fan-out events.

| Event | Direction | Payload |
|-------|-----------|---------|
| `message.new` | server → client | full message object |
| `conversation.updated` | server → client | updated conversation metadata |
| `typing.start` | client → server → recipient | `{ conversation_id }` |
| `typing.stop` | client → server → recipient | `{ conversation_id }` |
| `presence.online` | server → friends | `{ user_id }` |
| `presence.offline` | server → friends | `{ user_id }` |

### 5.5 Presence
- User is **online** when they have at least one active WebSocket connection.
- User is **offline** when all their connections drop.
- On connect/disconnect, the server broadcasts `presence.online` / `presence.offline` to all online friends.

### 5.6 Unread Counts
- `conversation_members` has a `last_read_at` column.
- Updated to `NOW()` whenever the user opens or focuses a conversation.
- Unread count = messages in the conversation with `created_at > last_read_at`.

---

## 6. Non-Functional Requirements

| Concern | Target |
|---------|--------|
| Latency | Message delivery < 300 ms on same-region network |
| Auth security | bcrypt cost ≥ 12; JWT stored in localStorage (XSS risk accepted for MVP) |
| API style | RESTful JSON for CRUD; WebSocket for real-time events |
| Data persistence | PostgreSQL (self-hosted in Docker Compose on the same VM) |
| Deployment | AWS / GCP / Azure cloud VM via Docker Compose |
| Multi-device | Server fans out WS events to all active sessions per user |
| Theme | Follows OS preference (light / dark via CSS `prefers-color-scheme`) |

---

## 7. Tech Stack

| Layer | Choice |
|-------|--------|
| Frontend | React + TypeScript, TailwindCSS, **shadcn/ui** |
| Backend | **Node.js (Fastify)** |
| Real-time | WebSocket (`ws` library) |
| Database | PostgreSQL |
| Auth | JWT (`jsonwebtoken`) |
| Container | Docker Compose |
| Hosting | AWS / GCP / Azure VM |

---

## 8. API Surface

### Auth
```
POST /api/auth/register
POST /api/auth/login
```

### Users
```
GET  /api/users/me
PUT  /api/users/me
GET  /api/users/search?q=<username>
```

### Friend Requests
```
GET  /api/friend-requests                  # pending incoming requests
POST /api/friend-requests                  { recipient_id }
PUT  /api/friend-requests/:id              { action: "accept" | "decline" }
```

### Friends
```
GET  /api/friends                          # accepted friends list
```

### Conversations
```
GET  /api/conversations
GET  /api/conversations/:id/messages?before=<cursor>
PUT  /api/conversations/:id/read           # update last_read_at
```

### Messages
```
POST /api/messages                         { recipient_id, body }
```

### WebSocket
```
WS   /ws?token=<jwt>
```

---

## 9. Data Model

```
users
  id            UUID PK
  username      VARCHAR(50) UNIQUE NOT NULL
  email         VARCHAR(255) UNIQUE NOT NULL
  password_hash TEXT NOT NULL
  display_name  VARCHAR(100)
  avatar_url    TEXT
  created_at    TIMESTAMPTZ

friend_requests
  id            UUID PK
  sender_id     UUID FK → users.id
  recipient_id  UUID FK → users.id
  status        VARCHAR(10) NOT NULL DEFAULT 'pending'  -- 'pending' | 'accepted' | 'declined'
  created_at    TIMESTAMPTZ
  updated_at    TIMESTAMPTZ
  UNIQUE (sender_id, recipient_id)

conversations
  id            UUID PK
  created_at    TIMESTAMPTZ

conversation_members
  conversation_id  UUID FK → conversations.id
  user_id          UUID FK → users.id
  last_read_at     TIMESTAMPTZ
  PRIMARY KEY (conversation_id, user_id)

messages
  id              UUID PK
  conversation_id UUID FK → conversations.id
  sender_id       UUID FK → users.id
  body            TEXT NOT NULL
  created_at      TIMESTAMPTZ
```

> **Note:** Online presence is tracked in-memory on the server (a `Map<userId, Set<WebSocket>>`), not in the database. No persistence needed for MVP.

---

## 10. UI Screens & Layout

### Layout
Classic 2-panel (Slack/Telegram Web style):
```
+------------------+-----------------------------+
| Friends / Chats  |  Alice  🟢 online           |
|------------------|  Alice is typing...         |
| 🟢 Alice  [2] >  |-----------------------------|
| ⚫ Bob            |  [10:01] Alice: hey!        |
| 🟢 Carol          |  [10:02] You: hello         |
|------------------|                             |
| [search users]   |  [input]         [Send]     |
+------------------+-----------------------------+
```

### Screen List
1. **Register** — username, email, password + submit
2. **Login** — email, password + submit
3. **Conversation List (sidebar)** — recent chats, unread count badge, online dot
4. **Chat View** — message history, typing indicator, input (Enter=send), retry on failure
5. **Friend Requests** — incoming requests with Accept / Decline actions
6. **User Search** — search bar + "Send Friend Request" action
7. **Profile Edit** — display name, avatar URL

### Theme
- Respects OS `prefers-color-scheme` (light / dark auto-switch).
- Built with shadcn/ui + Tailwind CSS variables for theming.

---

## 11. Milestones

| # | Milestone | Deliverable |
|---|-----------|-------------|
| M1 | DB schema + auth API | `users` table, register/login endpoints, JWT |
| M2 | Friend request system | `friend_requests` table, send/accept/decline API + WS events |
| M3 | Conversations + messages REST | Paginated history, `last_read_at`, unread counts |
| M4 | WebSocket core | Real-time message delivery, multi-device fan-out |
| M5 | Presence + typing | `presence.*` and `typing.*` WS events |
| M6 | Frontend: auth + friend flow | Register, login, user search, friend requests |
| M7 | Frontend: chat view | 2-panel layout, real-time messages, typing indicator, retry UX |
| M8 | Deployment | Docker Compose, cloud VM, env config, smoke test |

---

## 12. Key Decisions & Tradeoffs

| Decision | Choice | Tradeoff |
|----------|--------|----------|
| Contact model | Mutual friend request | More secure and intentional UX; adds `friend_requests` table and API surface |
| JWT storage | localStorage | Simpler; vulnerable to XSS — acceptable for portfolio scope |
| WS auth | Token in query param | Tokens appear in server access logs — acceptable for portfolio |
| Presence | In-memory Map | Fast, zero DB writes; lost on server restart (fine for single-server MVP) |
| Multi-device | Full fan-out | All active sessions receive events; `Map<userId, Set<WS>>` on server |
| Avatar | URL only | No S3 or upload logic needed in MVP |
| DB hosting | Self-hosted in Docker | Cheapest; no managed DB overhead; sufficient for portfolio traffic |

---

## 13. Success Criteria

- Two users can register, find each other via search, send/accept a friend request, and exchange messages in real time.
- Messages are delivered to all open tabs of the recipient simultaneously.
- Unread counts update correctly and persist across page refreshes.
- Online/offline presence updates in real time.
- Messages persist across page refreshes.
- All API endpoints return correct HTTP status codes and JSON error bodies.
- The app runs end-to-end with a single `docker compose up` and deploys to a cloud VM.
