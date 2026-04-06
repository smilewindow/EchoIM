import fp from 'fastify-plugin'
import { Redis } from 'ioredis'
import type { FastifyInstance } from 'fastify'

declare module 'fastify' {
  interface FastifyInstance {
    redis: { pub: Redis; sub: Redis }
  }
}

// Lua script: atomic connect — add member, return 1 if user went 0→1
const PRESENCE_CONNECT_SCRIPT = `
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local expireAt = now + tonumber(ARGV[2])
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now)
local before = redis.call('ZCARD', KEYS[1])
redis.call('ZADD', KEYS[1], expireAt, ARGV[1])
if before == 0 then
  return 1
end
return 0
`

// Lua script: atomic disconnect — remove self, return 1 if no active connections remain
const PRESENCE_DISCONNECT_SCRIPT = `
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local selfScore = redis.call('ZSCORE', KEYS[1], ARGV[1])
if not selfScore then
  return 0
end
redis.call('ZREM', KEYS[1], ARGV[1])
local alive = redis.call('ZCOUNT', KEYS[1], '(' .. now, '+inf')
if alive == 0 then
  redis.call('DEL', KEYS[1])
  return 1
end
return 0
`

// Lua script: heartbeat — extend own member's score (only if member exists)
const PRESENCE_HEARTBEAT_SCRIPT = `
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local expireAt = now + tonumber(ARGV[2])
redis.call('ZADD', KEYS[1], 'XX', expireAt, ARGV[1])
return 0
`

// Lua script: check online — non-destructive, returns 1 if any unexpired member
const PRESENCE_CHECK_SCRIPT = `
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local alive = redis.call('ZCOUNT', KEYS[1], '(' .. now, '+inf')
return alive > 0 and 1 or 0
`

// Lua script: sweep one key — remove expired members, return 1 if went >0→0
const PRESENCE_SWEEP_KEY_SCRIPT = `
local t = redis.call('TIME')
local now = tonumber(t[1]) * 1000 + math.floor(tonumber(t[2]) / 1000)
local before = redis.call('ZCARD', KEYS[1])
if before == 0 then return 0 end
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now)
local after = redis.call('ZCARD', KEYS[1])
if after == 0 and before > 0 then
  redis.call('DEL', KEYS[1])
  return 1
end
return 0
`

// Extend Redis type with custom Lua commands
declare module 'ioredis' {
  interface Redis {
    presenceConnect(key: string, member: string, leaseDurationMs: number): Promise<number>
    presenceDisconnect(key: string, member: string): Promise<number>
    presenceHeartbeat(key: string, member: string, leaseDurationMs: number): Promise<number>
    presenceCheck(key: string): Promise<number>
    presenceSweepKey(key: string): Promise<number>
  }
  interface ChainableCommander {
    presenceConnect(key: string, member: string, leaseDurationMs: number): ChainableCommander
    presenceDisconnect(key: string, member: string): ChainableCommander
    presenceHeartbeat(key: string, member: string, leaseDurationMs: number): ChainableCommander
    presenceCheck(key: string): ChainableCommander
    presenceSweepKey(key: string): ChainableCommander
  }
}

function createRedisClient(url: string): Redis {
  const client = new Redis(url, { lazyConnect: true })
  client.defineCommand('presenceConnect', {
    numberOfKeys: 1,
    lua: PRESENCE_CONNECT_SCRIPT,
  })
  client.defineCommand('presenceDisconnect', {
    numberOfKeys: 1,
    lua: PRESENCE_DISCONNECT_SCRIPT,
  })
  client.defineCommand('presenceHeartbeat', {
    numberOfKeys: 1,
    lua: PRESENCE_HEARTBEAT_SCRIPT,
  })
  client.defineCommand('presenceCheck', {
    numberOfKeys: 1,
    lua: PRESENCE_CHECK_SCRIPT,
  })
  client.defineCommand('presenceSweepKey', {
    numberOfKeys: 1,
    lua: PRESENCE_SWEEP_KEY_SCRIPT,
  })
  return client
}

async function redisPlugin(fastify: FastifyInstance) {
  const url = process.env['REDIS_URL'] ?? 'redis://localhost:6379'

  const pub = createRedisClient(url)
  const sub = createRedisClient(url)

  await pub.connect()
  await sub.connect()

  fastify.decorate('redis', { pub, sub })

  fastify.addHook('onClose', async () => {
    pub.disconnect()
    sub.disconnect()
  })
}

export default fp(redisPlugin, { name: 'redis' })
