# ---- Build stage ----
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src/ ./src/

RUN npm run build

# ---- Production stage ----
FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Compiled JS
COPY --from=builder /app/dist/ ./dist/

# SQL migrations (read at runtime by migrations-runner)
COPY src/db/migrations/ ./dist/db/migrations/

COPY docker-entrypoint.sh ./

EXPOSE 3000

ENTRYPOINT ["./docker-entrypoint.sh"]
