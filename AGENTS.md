# Repository Guidelines

## Project Structure & Module Organization
EchoIM is a small monorepo with a clear split between frontend and backend:
- `client/`: React 18 + Vite app. Main code lives in `client/src`, reusable UI primitives in `client/src/components/ui`, and shared helpers in `client/src/lib`.
- `server/`: Fastify + TypeScript API. The current entry point is `server/src/index.ts`; keep new routes, services, and database helpers under `server/src`.
- Root files: `docker-compose.yml` starts PostgreSQL, `.env.example` documents local configuration, and `prd.md` / `tasks.md` describe product scope and implementation order.

## Build, Test, and Development Commands
- `docker compose up -d postgres`: start the local PostgreSQL 16 instance.
- `npm run dev:client`: run the Vite dev server from the repo root.
- `npm run dev:server`: run the Fastify server with `tsx watch`.
- `npm run build --prefix client`: type-check and build the frontend bundle.
- `npm run build --prefix server`: compile backend TypeScript to `server/dist`.
- `npm run lint --prefix client` / `npm run lint --prefix server`: run ESLint.
- `npm run format --prefix client` / `npm run format --prefix server`: format `src/` files with Prettier.

## Coding Style & Naming Conventions
Use TypeScript with ESM imports throughout. Prettier enforces 2-space indentation, single quotes, no semicolons, trailing commas, and a 100-character line width. Name React components in `PascalCase`, hooks with a `use` prefix, and utilities or backend modules in `camelCase`. Keep generated shadcn/ui primitives isolated in `client/src/components/ui/`, and keep feature-specific code close to the feature it serves.

## Testing Guidelines
No automated test runner is configured yet. Until one is added, every PR should pass both lint commands and both build commands, smoke-test `GET /healthz`, and manually verify the affected UI or API flow. If you add non-trivial logic, include colocated `*.test.ts` or `*.test.tsx` files in the same PR instead of deferring coverage.

## Commit & Pull Request Guidelines
Recent commits use short, prefixed subjects such as `docs: add Claude Code repository guide`. Follow that pattern with focused, imperative messages like `feat:`, `fix:`, `docs:`, or `refactor:`. PRs should include a short summary, note which areas changed (`client`, `server`, or infra), call out env or schema updates, and attach screenshots for UI work or example requests/responses for API changes.

## Security & Configuration Tips
Copy `.env.example` for local setup and keep real secrets out of git. `POSTGRES_PASSWORD`, `DATABASE_URL`, and `JWT_SECRET` should stay local-only. For development, use the Docker Compose database instead of a shared external instance.

# Output Language

Always respond in Chinese

## 