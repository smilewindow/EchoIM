# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EchoIM is a real-time 1-on-1 chat application (portfolio project). Monorepo with `/server` (Fastify/Node.js) and `/client` (React + Vite + TypeScript). PostgreSQL via Docker Compose. Real-time via WebSocket.

**Current status:** Phases 1–4 complete (scaffold, schema, auth API, friends API). See `tasks.md` for remaining work.

## Repository Structure

```
/server       Fastify backend (Phases 1–4 implemented)
/client       React + Vite + TypeScript frontend (not yet started)
docker-compose.yml
prd.md        Full Product Requirements Document
tasks.md      12-phase task breakdown with dependency map
```

## Commands

Once scaffolded (Phase 1), the expected commands are:

```bash
# Start all services
docker compose up

# Server dev (from /server)
npm run dev

# Client dev (from /client)
npm run dev

# Lint (both packages)
npm run lint
```

Vitest integration tests are configured for the server. Run from `/server`:

```bash
npm test
```

Tests use a real PostgreSQL database (`TEST_DATABASE_URL`). Each suite calls `truncateAll()` in `beforeEach`. The client has no test runner yet.

After modifying any server source file, always run lint before considering the task done:

```bash
npm run lint --prefix server
```

## Architecture

### Backend (`/server`)
- **Framework:** Fastify with a `authenticate` hook (JWT verification, attaches `req.user`)
- **Database:** PostgreSQL via `pg`; raw SQL migrations (no ORM)
- **WebSocket:** `ws` library; Fastify handles the upgrade at `WS /ws?token=<jwt>`
- **Presence:** In-memory `Map<userId, Set<WebSocket>>` — not persisted, lost on restart
- **Message fan-out:** `broadcast(userId, event)` sends to all active WS sessions for that user (multi-device support)

### Frontend (`/client`)
- **State:** Zustand `authStore` holds JWT (localStorage) and current user
- **Routing:** React Router — `/login`, `/register`, `/` (protected)
- **Real-time:** `useWebSocket` hook manages WS connection lifecycle and reconnection
- **Optimistic UI:** Messages appended immediately as `pending`, updated to `failed` on error with retry button
- **Unread counts:** Computed server-side via `last_read_at` in `conversation_members`

### Data Model
Five tables: `users`, `friend_requests`, `conversations`, `conversation_members` (with `last_read_at`), `messages`. Friendship is determined by `friend_requests` rows with `status = 'accepted'` — no separate friends table.

### WebSocket Events
| Event | Direction | Notes |
|-------|-----------|-------|
| `message.new` | server → client | Full message object |
| `conversation.updated` | server → client | After read-receipt update |
| `typing.start` / `typing.stop` | client ↔ server ↔ recipient | Forwarded to recipient's sessions |
| `presence.online` / `presence.offline` | server → friends | On WS connect/disconnect |

## Key Decisions

- **Contacts are mutual:** users cannot message non-friends; friendship requires accepted request from both sides
- **JWT in localStorage + WS token as query param:** XSS risk accepted for portfolio scope
- **Cursor-based pagination:** 50 messages per page, cursor = `created_at` of oldest loaded message
- **Conversation auto-created** on first message between two friends (`POST /api/messages`)
- **Phases 6 and 9 can run in parallel** once Phase 5 (messages REST API) is complete
