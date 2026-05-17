import jwt from 'jsonwebtoken'
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import type { JwtPayload } from '../types/auth.js'
import { ApiErrors, sendApiError } from '../lib/api-errors.js'

// WeakMap stores the per-request user value (Fastify 5 getter/setter pattern)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const userStore = new WeakMap<any, { id: number }>()

export function registerAuthDecorator(fastify: FastifyInstance) {
  fastify.decorateRequest('user', {
    getter(this: FastifyRequest) {
      return userStore.get(this) ?? (null as unknown as { id: number })
    },
    setter(this: FastifyRequest, val: { id: number }) {
      userStore.set(this, val)
    },
  })
}

export async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  const authHeader = request.headers.authorization
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return sendApiError(reply, ApiErrors.authMissing)
  }

  const token = authHeader.slice(7)
  const secret = process.env['JWT_SECRET']!

  let decoded: unknown
  try {
    decoded = jwt.verify(token, secret)
  } catch {
    return sendApiError(reply, ApiErrors.authInvalid)
  }

  if (
    typeof decoded !== 'object' ||
    decoded === null ||
    !('id' in decoded) ||
    typeof (decoded as JwtPayload).id !== 'number'
  ) {
    return sendApiError(reply, ApiErrors.authInvalidPayload)
  }

  request.user = { id: (decoded as JwtPayload).id }
}
