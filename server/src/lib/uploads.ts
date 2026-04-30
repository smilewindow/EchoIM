import { join, resolve } from 'node:path'

export function getUploadsRoot(): string {
  const configuredRoot = process.env['UPLOADS_DIR']

  // 统一入口，避免开发环境和测试环境误用同一套本地上传文件。
  return configuredRoot ? resolve(configuredRoot) : join(process.cwd(), 'uploads')
}

export function getAvatarUploadsDir(): string {
  return join(getUploadsRoot(), 'avatars')
}

export function getMessageUploadsDir(): string {
  return join(getUploadsRoot(), 'messages')
}
