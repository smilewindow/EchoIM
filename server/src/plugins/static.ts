import fastifyStatic from '@fastify/static'
import type { FastifyPluginAsync } from 'fastify'
import { getUploadsRoot } from '../lib/uploads.js'

const staticPlugin: FastifyPluginAsync = async (fastify) => {
  await fastify.register(fastifyStatic, {
    root: getUploadsRoot(),
    prefix: '/uploads/',
    decorateReply: false,
  })
}

export default staticPlugin
