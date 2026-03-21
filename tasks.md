# EchoIM — Task Breakdown

Each task is small enough to complete in one session. Tasks within a phase are ordered by dependency — complete them top-to-bottom. Check off `[x]` as you go.

**Status legend:** `[ ]` todo · `[x]` done · `[-]` skipped

---

## Phase 1 — Project Scaffolding

- [x] **1.1** Initialize monorepo structure: `/server` (Fastify) and `/client` (React + Vite + TS)
- [x] **1.2** Set up `server`: install Fastify, `pg`, `bcrypt`, `jsonwebtoken`, `ws`, `dotenv`
- [x] **1.3** Set up `client`: install TailwindCSS, shadcn/ui, React Router
- [x] **1.4** Write `docker-compose.yml` with `postgres` service and env vars; confirm `pg` connects
- [x] **1.5** Add `eslint` + `prettier` configs to both packages; confirm lint passes

---

## Phase 2 — Database Schema

- [x] **2.1** Write migration: `users` table (`id`, `username`, `email`, `password_hash`, `display_name`, `avatar_url`, `created_at`)
- [x] **2.2** Write migration: `friend_requests` table (`id`, `sender_id`, `recipient_id`, `status`, `created_at`, `updated_at`)
- [x] **2.3** Write migration: `conversations` + `conversation_members` tables (`last_read_at` included)
- [x] **2.4** Write migration: `messages` table
- [x] **2.5** Add DB indexes: `messages(conversation_id, created_at)`, `friend_requests(recipient_id, status)`

---

## Phase 3 — Auth API

- [x] **3.1** `POST /api/auth/register` — validate input, hash password (bcrypt cost 12), insert user, return JWT
- [x] **3.2** `POST /api/auth/login` — verify credentials, return JWT
- [x] **3.3** Write `authenticate` Fastify hook that verifies JWT and attaches `req.user`
- [x] **3.4** `GET /api/users/me` — return current user profile (protected)
- [x] **3.5** `PUT /api/users/me` — update `display_name` and `avatar_url` (protected)
- [x] **3.6** Vitest integration tests (22 cases): register, login, auth errors, profile get/update — replaced manual-only approach; curl smoke tests were done during development

> **Testing infrastructure introduced here.** Vitest + real test DB (`TEST_DATABASE_URL`). Key helpers in `server/tests/helpers/`: `buildApp()` (spins up Fastify instance), `truncateAll()` (resets DB between tests), `registerUser()` (seed shortcut). Run with `npm test` from `/server`. All subsequent backend phases follow this same pattern.

---

## Phase 4 — User Search & Friend Requests API

- [x] **4.1** `GET /api/users/search?q=` — case-insensitive partial match on `username`, exclude self
- [x] **4.2** `POST /api/friend-requests` — create pending request; reject duplicate or reversed existing request
- [x] **4.3** `GET /api/friend-requests` — return pending incoming requests for current user
- [x] **4.4** `PUT /api/friend-requests/:id` — accept or decline; on accept, do nothing extra (friendship is queried from `friend_requests` where status = accepted)
- [x] **4.5** `GET /api/friends` — return all users where a mutual accepted request exists
- [x] **4.6** Manual test: two users, send request, accept, verify friends list
- [x] **4.7** Write integration tests: user search, send/accept/decline friend requests, friends list, duplicate-request and self-request rejection

---

## Phase 5 — Conversations & Messages REST API

- [x] **5.1** `POST /api/messages` — accept `{ recipient_id, body }`; verify friendship; auto-create conversation if none exists; insert message; return message object
- [x] **5.2** `GET /api/conversations` — list conversations for current user, sorted by latest message, include unread count (`messages after last_read_at`)
- [x] **5.3** `GET /api/conversations/:id/messages?before=<cursor>` — paginated history (50 per page, cursor = message `id` of oldest loaded message)
- [x] **5.4** `PUT /api/conversations/:id/read` — set `last_read_at = NOW()` for current user
- [x] **5.5** Manual test: send messages, check pagination, check unread count decrements on read
- [x] **5.6** Write integration tests: send message (auto-create conversation), conversation list with unread counts, cursor pagination, read receipts, friendship guard

---

## Phase 6 — WebSocket Server

- [x] **6.1** Set up `WS /ws?token=<jwt>` endpoint in Fastify; authenticate on upgrade; store connection in `Map<userId, Set<WebSocket>>`
- [x] **6.2** Implement `broadcast(userId, event)` helper — sends to all active sessions for that user
- [x] **6.3** On `POST /api/messages` success: call `broadcast(recipientId, { type: 'message.new', data: message })` and `broadcast(senderId, ...)` for sender's other tabs
- [x] **6.4** On `PUT /api/conversations/:id/read` success: broadcast `conversation.updated` to sender's other tabs
- [x] **6.5** Handle WS client message `typing.start` / `typing.stop` — forward to recipient's active sessions
- [x] **6.6** On WS connect: if user now has ≥ 1 connection, broadcast `presence.online` to all online friends; also send snapshot of already-online friends back to the newcomer
- [x] **6.7** On WS disconnect: if user now has 0 connections, broadcast `presence.offline` to all online friends; guard against stale async results on quick reconnect
- [-] **6.8** Manual test with two browser tabs: confirm real-time delivery and presence events
- [x] **6.9** Write integration tests: WS auth (valid/invalid token), message broadcast, typing events forwarded, presence online/offline, presence snapshot

---

## Phase 7 — Frontend: Auth Screens

- [x] **7.1** Set up React Router: routes for `/login`, `/register`, `/` (protected), redirect logic
- [x] **7.2** Create `authStore` (Zustand or React context): stores JWT in `localStorage`, exposes `login()`, `logout()`, `user`
- [x] **7.3** Build `RegisterPage` — form with username, email, password; calls `POST /api/auth/register`; redirects to `/` on success
- [x] **7.4** Build `LoginPage` — form with email, password; calls `POST /api/auth/login`; redirects to `/` on success
- [x] **7.5** Add protected route wrapper — redirects unauthenticated users to `/login`

---

## Phase 8 — Frontend: Friends Flow

- [x] **8.1** Build `UserSearchPanel` — input debounced to `GET /api/users/search`; shows results with "Send Request" button
- [x] **8.2** Build `FriendRequestsPanel` — lists pending incoming requests; Accept / Decline buttons calling `PUT /api/friend-requests/:id`
- [x] **8.3** Build `FriendsList` component — calls `GET /api/friends`; shows display name + online dot (placeholder for now)
- [x] **8.4** Wire up friend request badge: poll `GET /api/friend-requests` on mount, show count indicator if > 0

---

## Phase 9 — Frontend: Chat View (REST only)

- [ ] **9.1** Build 2-panel shell layout: left sidebar (`FriendsList` + `ConversationList`), right panel (`ChatView`)
- [ ] **9.2** Build `ConversationList` — calls `GET /api/conversations`; shows latest message preview + unread badge; sorted by recency
- [ ] **9.3** Build `ChatView` — loads `GET /api/conversations/:id/messages`; renders message bubbles (self right, other left)
- [ ] **9.4** Implement infinite scroll / "load older messages" button using cursor pagination
- [ ] **9.5** Build `MessageInput` — textarea, Enter=send, Shift+Enter=newline; calls `POST /api/messages`
- [ ] **9.6** Optimistic message add: append message to local list immediately on send, mark as `pending`
- [ ] **9.7** On send failure: mark message as `failed`, show retry button that re-calls `POST /api/messages`
- [ ] **9.8** Call `PUT /api/conversations/:id/read` when user opens or focuses a conversation; update unread count locally

---

## Phase 10 — Frontend: WebSocket & Real-Time

- [ ] **10.1** Create `useWebSocket` hook — connects to `WS /ws?token=<jwt>` on mount, reconnects on disconnect, exposes `onMessage` callback
- [ ] **10.2** Handle `message.new` event — append message to the active conversation if open; update conversation list preview + unread count
- [ ] **10.3** Handle `conversation.updated` event — refresh conversation list order/preview
- [ ] **10.4** Handle `typing.start` / `typing.stop` — show/hide "Alice is typing..." indicator in `ChatView`
- [ ] **10.5** Send `typing.start` from `MessageInput` on keydown (debounced); send `typing.stop` on blur or after 3 s of inactivity
- [ ] **10.6** Handle `presence.online` / `presence.offline` — update online status dots in `FriendsList` and `ChatView` header
- [ ] **10.7** On reconnect: fetch messages since last known `created_at` to backfill any missed messages

---

## Phase 11 — Polish & Theme

- [ ] **11.1** Apply shadcn/ui theme variables; add `dark:` Tailwind classes throughout; confirm auto-switch with OS setting
- [ ] **11.2** Add loading skeletons for conversation list and message history
- [ ] **11.3** Add empty states: no conversations, no friends, no search results
- [ ] **11.4** Scroll chat panel to bottom on new message (unless user has scrolled up)
- [ ] **11.5** Add toast notifications for errors (failed login, network error, etc.) using shadcn/ui `Toast`
- [ ] **11.6** Build `ProfileEditPage` — display name + avatar URL form; calls `PUT /api/users/me`

---

## Phase 12 — Deployment

- [ ] **12.1** Add `Dockerfile` for the backend (Node.js); multi-stage build
- [ ] **12.2** Add `Dockerfile` for the frontend (Vite build → nginx static serve)
- [ ] **12.3** Update `docker-compose.yml` to include all three services: `postgres`, `server`, `client`
- [ ] **12.4** Externalize all secrets to `.env` file; add `.env.example`; confirm nothing is hardcoded
- [ ] **12.5** Provision cloud VM (AWS EC2 / GCP Compute Engine / Azure VM); install Docker + Compose
- [ ] **12.6** Deploy: `git pull` + `docker compose up -d` on VM; confirm app is reachable via public IP
- [ ] **12.7** Smoke test end-to-end on the live server: register two accounts, add friend, chat in real time

---

## Dependency Map

```
Phase 1 (scaffold)
  └─ Phase 2 (schema)
       └─ Phase 3 (auth API)
            ├─ Phase 4 (friends API)
            │    └─ Phase 5 (messages API)
            │         └─ Phase 6 (WebSocket)
            └─ Phase 7 (frontend auth)
                 └─ Phase 8 (frontend friends)
                      └─ Phase 9 (frontend chat — REST)
                           └─ Phase 10 (frontend — real-time)
                                └─ Phase 11 (polish)
                                     └─ Phase 12 (deploy)
```

> Phases 6 and 9 can be developed in parallel once Phase 5 is done.
> Phase 11 can be interleaved with Phases 9–10.
