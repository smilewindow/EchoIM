export interface JwtPayload {
  id: number
}

declare module 'fastify' {
  interface FastifyRequest {
    user: { id: number }
  }
}
