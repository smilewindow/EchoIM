# ---- Build stage ----
FROM node:20-alpine AS builder

RUN apk add --no-cache python3 make g++

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src/ ./src/

RUN npm run build

# ---- Production stage ----
FROM node:20-alpine

RUN apk add --no-cache python3 make g++

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && apk del python3 make g++

# Compiled JS
COPY --from=builder /app/dist/ ./dist/

# SQL migrations (read at runtime by migrations-runner)
COPY src/db/migrations/ ./dist/db/migrations/

COPY docker-entrypoint.sh ./

EXPOSE 3000

ENTRYPOINT ["./docker-entrypoint.sh"]
