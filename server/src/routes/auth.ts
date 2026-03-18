import bcrypt from 'bcrypt'
import jwt from 'jsonwebtoken'
import type { FastifyPluginAsync } from 'fastify'

const authRoutes: FastifyPluginAsync = async (fastify) => {
  fastify.post('/register', {
    schema: {
      body: {
        type: 'object',
        required: ['username', 'email', 'password'],
        additionalProperties: false,
        properties: {
          username: { type: 'string', minLength: 3, maxLength: 50 },
          email: { type: 'string', minLength: 1, maxLength: 254 },
          password: { type: 'string', minLength: 8, maxLength: 128 },
        },
      },
    },
  }, async (request, reply) => {
    const { username: rawUsername, email: rawEmail, password } = request.body as {
      username: string
      email: string
      password: string
    }

    const username = rawUsername.trim()
    const email = rawEmail.trim().toLowerCase()

    if (username.length < 3) {
      return reply.status(400).send({ error: 'Username must be at least 3 characters' })
    }
    if (email.length < 3 || !email.includes('@')) {
      return reply.status(400).send({ error: 'Invalid email address' })
    }

    const passwordHash = await bcrypt.hash(password, 12)

    let user: { id: number; username: string; email: string; display_name: string | null; avatar_url: string | null }
    try {
      const result = await fastify.pool.query(
        `INSERT INTO users (username, email, password_hash)
         VALUES ($1, $2, $3)
         RETURNING id, username, email, display_name, avatar_url`,
        [username, email, passwordHash]
      )
      user = result.rows[0]
    } catch (err: unknown) {
      if (
        typeof err === 'object' &&
        err !== null &&
        'code' in err &&
        (err as { code: string }).code === '23505'
      ) {
        const constraint = (err as { constraint?: string }).constraint ?? ''
        if (constraint.includes('email')) {
          return reply.status(409).send({ error: 'Email already in use' })
        }
        if (constraint.includes('username')) {
          return reply.status(409).send({ error: 'Username already taken' })
        }
        return reply.status(409).send({ error: 'Account already exists' })
      }
      throw err
    }

    const token = jwt.sign({ id: user.id }, process.env['JWT_SECRET']!, { expiresIn: '7d' })

    return reply.status(201).send({ token, user })
  })

  fastify.post('/login', {
    schema: {
      body: {
        type: 'object',
        required: ['email', 'password'],
        additionalProperties: false,
        properties: {
          email: { type: 'string', minLength: 1, maxLength: 254 },
          password: { type: 'string', minLength: 1 },
        },
      },
    },
  }, async (request, reply) => {
    const { email: rawEmail, password } = request.body as { email: string; password: string }
    const email = rawEmail.trim().toLowerCase()

    const result = await fastify.pool.query(
      `SELECT id, username, email, password_hash, display_name, avatar_url
       FROM users WHERE email = $1`,
      [email]
    )

    const row = result.rows[0]
    if (!row || !(await bcrypt.compare(password, row.password_hash))) {
      return reply.status(401).send({ error: 'Invalid email or password' })
    }

    const token = jwt.sign({ id: row.id }, process.env['JWT_SECRET']!, { expiresIn: '7d' })
    const user = {
      id: row.id as number,
      username: row.username as string,
      email: row.email as string,
      display_name: row.display_name as string | null,
      avatar_url: row.avatar_url as string | null,
    }

    return reply.status(200).send({ token, user })
  })
}

export default authRoutes
