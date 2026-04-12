# 头像上传实现计划 (v4)

> **给 Agent 执行者：** 必须使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 按任务逐步实现。步骤使用 checkbox（`- [ ]`）语法跟踪进度。

**目标：** 允许用户上传图片作为头像，前端压缩、后端校验、多实例兼容存储。

**架构：**
- **前端：** Canvas API 压缩图片至 ≤800x800，目标 ≤500KB（自适应质量/尺寸缩减）
- **后端：** `sharp` 校验并标准化为 400x400 JPEG（透明区域铺白底），存入共享 Docker 卷
- **存储：** Docker 命名卷 `avatar-uploads` 挂载到所有 server 实例
- **代理：** Vite dev server 和 nginx 均代理 `/uploads` 到 Fastify
- **清理：** 上传路由和资料更新路由都处理旧文件删除（尽力而为，记录日志）

**技术栈：** Canvas API（压缩）、`sharp`（图片处理）、`@fastify/multipart`、`@fastify/static`、Docker 卷

---

## 文件结构

```
server/
├── src/
│   ├── app.ts                      # 修改：注册 static + upload 插件
│   ├── plugins/
│   │   └── static.ts               # 新建：@fastify/static 配置
│   └── routes/
│       ├── upload.ts               # 新建：POST /api/upload/avatar
│       └── users.ts                # 修改：头像变更时删除旧本地文件
├── uploads/
│   └── avatars/
│       └── .gitkeep                # 新建：占位文件以提交空目录
└── tests/
    ├── static.test.ts              # 新建：静态文件服务测试
    └── upload.test.ts              # 新建：上传端点测试

client/
├── src/
│   ├── lib/
│   │   ├── api.ts                  # 修改：添加 uploadAvatar 函数
│   │   └── image.ts                # 新建：Canvas 压缩工具
│   ├── pages/
│   │   └── ProfileEditPage.tsx     # 修改：添加文件选择和上传
│   └── locales/
│       ├── en.json                 # 修改：添加上传相关文案
│       └── zh.json                 # 修改：添加上传相关文案
├── vite.config.ts                  # 修改：添加 /uploads 代理
└── nginx.conf                      # 修改：添加 /uploads 代理

docker-compose.yml                  # 修改：添加 avatar-uploads 卷
```

---

## 任务 1：安装后端依赖

**文件：**
- 修改：`server/package.json`

- [ ] **步骤 1：安装 @fastify/multipart、@fastify/static 和 sharp**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm install @fastify/multipart @fastify/static sharp
```

注意：`sharp` 自带 TypeScript 类型定义，无需安装 `@types/sharp`。

- [ ] **步骤 2：验证安装**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && node -e "require('sharp')"
```

预期：无报错（sharp 原生绑定正常工作）

- [ ] **步骤 3：提交**

```bash
git add server/package.json server/package-lock.json
git commit -m "chore(server): add @fastify/multipart, @fastify/static, sharp"
```

---

## 任务 2：创建上传目录和 Docker 卷

**文件：**
- 新建：`server/uploads/avatars/.gitkeep`
- 新建：`server/.gitignore`
- 修改：`docker-compose.yml`

- [ ] **步骤 1：创建目录和 .gitkeep**

执行：
```bash
mkdir -p /Users/xuyuqin/Documents/EchoIM/server/uploads/avatars
touch /Users/xuyuqin/Documents/EchoIM/server/uploads/avatars/.gitkeep
```

- [ ] **步骤 2：创建 server/.gitignore 配置正确规则**

新建 `server/.gitignore`：

```gitignore
# 上传文件
uploads/*
!uploads/avatars/
uploads/avatars/*
!uploads/avatars/.gitkeep
```

- [ ] **步骤 3：验证 .gitkeep 被跟踪**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM && git add server/uploads/avatars/.gitkeep --dry-run
```

预期：输出显示 `add 'server/uploads/avatars/.gitkeep'`

- [ ] **步骤 4：在 docker-compose.yml 中添加 avatar-uploads 卷**

修改 `docker-compose.yml`：

在底部 `volumes:` 部分添加：
```yaml
volumes:
  postgres-data:
  redis-data:
  avatar-uploads:
```

在 `server:` 服务中添加卷挂载（在 `ports:` 之后）：
```yaml
  server:
    # ... 现有配置 ...
    volumes:
      - avatar-uploads:/app/uploads
```

在 `server-1:` 服务中添加卷挂载：
```yaml
  server-1:
    # ... 现有配置 ...
    volumes:
      - avatar-uploads:/app/uploads
```

在 `server-2:` 服务中添加卷挂载：
```yaml
  server-2:
    # ... 现有配置 ...
    volumes:
      - avatar-uploads:/app/uploads
```

- [ ] **步骤 5：提交**

```bash
git add server/uploads/avatars/.gitkeep server/.gitignore docker-compose.yml
git commit -m "chore: add uploads directory and shared Docker volume"
```

---

## 任务 3：为 Vite 和 Nginx 添加 /uploads 代理

**文件：**
- 修改：`client/vite.config.ts`
- 修改：`client/nginx.conf`

- [ ] **步骤 1：在 vite.config.ts 中添加 /uploads 代理**

修改 `client/vite.config.ts`，在 `proxy` 对象中添加：

```typescript
proxy: {
  '/api': {
    target: apiOrigin,
    changeOrigin: true,
  },
  '/ws': {
    target: wsOrigin,
    ws: true,
  },
  '/uploads': {
    target: apiOrigin,
    changeOrigin: true,
  },
},
```

- [ ] **步骤 2：在 nginx.conf 中添加 /uploads 代理**

修改 `client/nginx.conf`，在 `# SPA fallback` 之前添加：

```nginx
# 上传文件代理
location /uploads/ {
    proxy_pass http://server:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_valid 200 1d;
    add_header Cache-Control "public, max-age=86400";
}
```

- [ ] **步骤 3：提交**

```bash
git add client/vite.config.ts client/nginx.conf
git commit -m "feat(client): add /uploads proxy to Vite and nginx"
```

---

## 任务 4：创建静态文件插件

**文件：**
- 新建：`server/src/plugins/static.ts`
- 修改：`server/src/app.ts`
- 新建：`server/tests/static.test.ts`

- [ ] **步骤 1：编写静态插件测试**

新建 `server/tests/static.test.ts`：

```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { mkdir, writeFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { getApp } from './helpers.js'
import type { App } from './helpers.js'

describe('Static file serving', () => {
  let app: App
  const uploadsDir = join(process.cwd(), 'uploads', 'avatars')
  const testFile = 'test-static.txt'
  const testFilePath = join(uploadsDir, testFile)

  beforeAll(async () => {
    await mkdir(uploadsDir, { recursive: true })
    await writeFile(testFilePath, 'hello static')
    app = await getApp()
  })

  afterAll(async () => {
    await app.close()
    await rm(testFilePath, { force: true })
  })

  it('serves files from /uploads/avatars/', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/uploads/avatars/${testFile}`,
    })
    expect(res.statusCode).toBe(200)
    expect(res.body).toBe('hello static')
  })

  it('returns 404 for non-existent files', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/uploads/avatars/does-not-exist.png',
    })
    expect(res.statusCode).toBe(404)
  })
})
```

- [ ] **步骤 2：运行测试验证失败**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test -- static.test.ts
```

预期：FAIL — static 插件未注册

- [ ] **步骤 3：创建静态插件**

新建 `server/src/plugins/static.ts`：

```typescript
import fastifyStatic from '@fastify/static'
import { join } from 'node:path'
import type { FastifyPluginAsync } from 'fastify'

const staticPlugin: FastifyPluginAsync = async (fastify) => {
  await fastify.register(fastifyStatic, {
    root: join(process.cwd(), 'uploads'),
    prefix: '/uploads/',
    decorateReply: false,
  })
}

export default staticPlugin
```

- [ ] **步骤 4：在 app.ts 中注册静态插件**

修改 `server/src/app.ts`：

添加导入：
```typescript
import staticPlugin from './plugins/static.js'
```

在 `app.get('/healthz', ...)` 之后添加：
```typescript
await app.register(staticPlugin)
```

- [ ] **步骤 5：运行测试验证通过**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test -- static.test.ts
```

预期：PASS

- [ ] **步骤 6：运行 lint**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm run lint
```

预期：无错误

- [ ] **步骤 7：提交**

```bash
git add server/src/plugins/static.ts server/src/app.ts server/tests/static.test.ts
git commit -m "feat(server): add static file serving for /uploads"
```

---

## 任务 5：创建带 Sharp 处理的上传路由

**文件：**
- 新建：`server/src/routes/upload.ts`
- 修改：`server/src/app.ts`
- 新建：`server/tests/upload.test.ts`

- [ ] **步骤 1：编写上传端点测试**

新建 `server/tests/upload.test.ts`：

```typescript
import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import sharp from 'sharp'
import { rm, readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { getApp, truncateAll, registerUser } from './helpers.js'
import type { App } from './helpers.js'

describe('POST /api/upload/avatar', () => {
  let app: App
  let token: string
  let userId: number
  const uploadsDir = join(process.cwd(), 'uploads', 'avatars')

  beforeAll(async () => {
    app = await getApp()
  })

  afterAll(async () => {
    await app.close()
  })

  beforeEach(async () => {
    await truncateAll(app)
    const result = await registerUser(app)
    token = result.token
    userId = result.user.id
    // 清理测试上传文件
    const files = await readdir(uploadsDir).catch(() => [])
    for (const file of files) {
      if (file !== '.gitkeep') {
        await rm(join(uploadsDir, file), { force: true })
      }
    }
  })

  it('returns 401 when unauthenticated', async () => {
    const form = createMultipartForm('avatar', Buffer.from('fake'), 'test.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: form.headers,
      payload: form.body,
    })
    expect(res.statusCode).toBe(401)
  })

  it('returns 400 when no file provided (empty multipart)', async () => {
    const form = createEmptyMultipartForm()
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toBe('No file provided')
  })

  it('returns 400 for invalid image (not decodable by sharp)', async () => {
    const form = createMultipartForm('avatar', Buffer.from('not an image'), 'test.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(400)
    expect(res.json().error).toContain('Invalid image')
  })

  it('returns 200 and updates user avatar_url for valid PNG', async () => {
    // 最小合法 PNG（1x1 透明）
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'avatar.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(200)
    const data = res.json<{ avatar_url: string }>()
    expect(data.avatar_url).toMatch(/^\/uploads\/avatars\/\d+-\d+\.jpg$/)

    // 验证用户记录已更新
    const userRes = await app.inject({
      method: 'GET',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${token}` },
    })
    expect(userRes.json().avatar_url).toBe(data.avatar_url)
  })

  it('returns 401 when token is valid but user no longer exists', async () => {
    // 获取 token 后删除用户
    await app.pool.query('DELETE FROM users WHERE id = $1', [userId])

    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'avatar.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: {
        authorization: `Bearer ${token}`,
        ...form.headers,
      },
      payload: form.body,
    })
    expect(res.statusCode).toBe(401)
    expect(res.json().error).toBe('User no longer exists')

    // 验证没有残留孤儿文件
    const files = await readdir(uploadsDir)
    const avatarFiles = files.filter((f) => f.startsWith(`${userId}-`))
    expect(avatarFiles).toHaveLength(0)
  })

  it('deletes old avatar file when uploading new one', async () => {
    // 上传第一个头像
    const png1 = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form1 = createMultipartForm('avatar', png1, 'avatar1.png', 'image/png')
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form1.headers },
      payload: form1.body,
    })
    const oldUrl = res1.json<{ avatar_url: string }>().avatar_url
    const oldFilename = oldUrl.split('/').pop()!

    // 上传第二个头像
    const form2 = createMultipartForm('avatar', png1, 'avatar2.png', 'image/png')
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form2.headers },
      payload: form2.body,
    })
    expect(res2.statusCode).toBe(200)

    // 旧文件应该已被删除
    const files = await readdir(uploadsDir)
    expect(files).not.toContain(oldFilename)
  })

  it('processes image to JPEG format', async () => {
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'avatar.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form.headers },
      payload: form.body,
    })
    const url = res.json<{ avatar_url: string }>().avatar_url
    const filename = url.split('/').pop()!
    const filepath = join(uploadsDir, filename)

    // 文件应为 JPEG（魔数：FF D8）
    const fileBuffer = await readFile(filepath)
    expect(fileBuffer[0]).toBe(0xff)
    expect(fileBuffer[1]).toBe(0xd8)
  })

  it('flattens transparent PNG to white background instead of black', async () => {
    // 与其他测试相同的 1x1 透明 PNG
    const pngBuffer = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
      0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ])
    const form = createMultipartForm('avatar', pngBuffer, 'transparent.png', 'image/png')
    const res = await app.inject({
      method: 'POST',
      url: '/api/upload/avatar',
      headers: { authorization: `Bearer ${token}`, ...form.headers },
      payload: form.body,
    })
    expect(res.statusCode).toBe(200)
    const url = res.json<{ avatar_url: string }>().avatar_url
    const filename = url.split('/').pop()!
    const filepath = join(uploadsDir, filename)

    // 用 sharp 读取输出 JPEG，检查左上角像素为白色而非黑色
    const { data } = await sharp(await readFile(filepath))
      .raw()
      .toBuffer({ resolveWithObject: true })
    // 前 3 字节 = 像素 (0,0) 的 R、G、B
    expect(data[0]).toBeGreaterThan(250) // R ≈ 255
    expect(data[1]).toBeGreaterThan(250) // G ≈ 255
    expect(data[2]).toBeGreaterThan(250) // B ≈ 255
  })
})

function createMultipartForm(
  fieldName: string,
  fileContent: Buffer,
  fileName: string,
  contentType: string,
) {
  const boundary = '----FormBoundary' + Math.random().toString(36).substring(2)
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\n`),
    Buffer.from(`Content-Disposition: form-data; name="${fieldName}"; filename="${fileName}"\r\n`),
    Buffer.from(`Content-Type: ${contentType}\r\n\r\n`),
    fileContent,
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ])
  return {
    headers: { 'content-type': `multipart/form-data; boundary=${boundary}` },
    body,
  }
}

function createEmptyMultipartForm() {
  const boundary = '----FormBoundary' + Math.random().toString(36).substring(2)
  const body = Buffer.from(`--${boundary}--\r\n`)
  return {
    headers: { 'content-type': `multipart/form-data; boundary=${boundary}` },
    body,
  }
}
```

- [ ] **步骤 2：运行测试验证失败**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test -- upload.test.ts
```

预期：FAIL — 路由不存在（404）

- [ ] **步骤 3：创建上传路由**

新建 `server/src/routes/upload.ts`：

```typescript
import type { FastifyPluginAsync } from 'fastify'
import fastifyMultipart from '@fastify/multipart'
import sharp from 'sharp'
import { mkdir, writeFile, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { authenticate } from '../hooks/authenticate.js'

const MAX_FILE_SIZE = 10 * 1024 * 1024 // 10MB（前端已压缩再上传）
const OUTPUT_SIZE = 400
const OUTPUT_QUALITY = 80
const UPLOADS_DIR = join(process.cwd(), 'uploads', 'avatars')

const uploadRoutes: FastifyPluginAsync = async (fastify) => {
  await fastify.register(fastifyMultipart, {
    limits: { fileSize: MAX_FILE_SIZE },
  })

  fastify.addHook('preHandler', authenticate)

  fastify.post('/avatar', async (request, reply) => {
    const file = await request.file()

    if (!file) {
      return reply.status(400).send({ error: 'No file provided' })
    }

    const buffer = await file.toBuffer()

    // 使用 sharp 校验和处理（隐式校验魔数）
    let processedBuffer: Buffer
    try {
      processedBuffer = await sharp(buffer)
        .flatten({ background: { r: 255, g: 255, b: 255 } })
        .resize(OUTPUT_SIZE, OUTPUT_SIZE, {
          fit: 'cover',
          position: 'center',
        })
        .jpeg({ quality: OUTPUT_QUALITY })
        .toBuffer()
    } catch {
      return reply.status(400).send({ error: 'Invalid image file' })
    }

    // 生成文件名
    const filename = `${request.user.id}-${Date.now()}.jpg`
    const filepath = join(UPLOADS_DIR, filename)
    const avatarUrl = `/uploads/avatars/${filename}`

    // 确保目录存在
    await mkdir(UPLOADS_DIR, { recursive: true })

    // 更新前获取旧头像 URL
    const oldAvatarResult = await fastify.pool.query(
      'SELECT avatar_url FROM users WHERE id = $1',
      [request.user.id],
    )

    // 处理过程中用户可能已被删除
    if (oldAvatarResult.rowCount === 0) {
      return reply.status(401).send({ error: 'User no longer exists' })
    }

    const oldAvatarUrl = oldAvatarResult.rows[0]?.avatar_url as string | null

    // 保存文件并更新数据库 — 失败时清理文件
    try {
      await writeFile(filepath, processedBuffer)

      const updateResult = await fastify.pool.query(
        'UPDATE users SET avatar_url = $1 WHERE id = $2',
        [avatarUrl, request.user.id],
      )

      // 在 SELECT 和 UPDATE 之间用户被删除
      if (updateResult.rowCount === 0) {
        await rm(filepath, { force: true }).catch(() => {})
        return reply.status(401).send({ error: 'User no longer exists' })
      }
    } catch (err) {
      // 数据库出错时清理文件，然后重新抛出
      await rm(filepath, { force: true }).catch(() => {})
      throw err
    }

    // 如果旧头像是本地上传的则删除（尽力而为，不影响请求）
    if (oldAvatarUrl?.startsWith('/uploads/avatars/')) {
      const oldFilename = oldAvatarUrl.split('/').pop()
      if (oldFilename && oldFilename !== filename) {
        await rm(join(UPLOADS_DIR, oldFilename), { force: true }).catch((err) => {
          fastify.log.warn({ err, oldFilename }, 'failed to cleanup old avatar file')
        })
      }
    }

    return reply.status(200).send({ avatar_url: avatarUrl })
  })
}

export default uploadRoutes
```

- [ ] **步骤 4：在 app.ts 中注册上传路由**

修改 `server/src/app.ts`：

添加导入：
```typescript
import uploadRoutes from './routes/upload.js'
```

在 `conversationRoutes` 注册之后添加：
```typescript
await app.register(uploadRoutes, { prefix: '/api/upload' })
```

- [ ] **步骤 5：运行测试验证通过**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test -- upload.test.ts
```

预期：PASS

- [ ] **步骤 6：运行完整测试套件**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test
```

预期：全部通过

- [ ] **步骤 7：运行 lint**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm run lint
```

预期：无错误

- [ ] **步骤 8：提交**

```bash
git add server/src/routes/upload.ts server/src/app.ts server/tests/upload.test.ts
git commit -m "feat(server): add avatar upload endpoint with sharp processing"
```

---

## 任务 6：更新 Users 路由清理旧头像文件

**文件：**
- 修改：`server/src/routes/users.ts`
- 修改：`server/tests/users.test.ts`

- [ ] **步骤 1：添加资料更新时头像清理的测试**

在 `server/tests/users.test.ts` 的 `describe('PUT /api/users/me', ...)` 中添加：

```typescript
it('deletes old local avatar file when avatar_url changes to external URL', async () => {
  const uploadsDir = join(process.cwd(), 'uploads', 'avatars')
  await mkdir(uploadsDir, { recursive: true })

  // 模拟一个已存在的本地头像
  const oldFilename = `${1}-${Date.now()}.jpg`
  const oldFilepath = join(uploadsDir, oldFilename)
  const oldAvatarUrl = `/uploads/avatars/${oldFilename}`
  await writeFile(oldFilepath, Buffer.from('fake image'))

  // 将用户头像设为本地文件
  await app.pool.query('UPDATE users SET avatar_url = $1 WHERE username = $2', [
    oldAvatarUrl,
    'alice',
  ])

  // 更新为外部 URL
  const res = await app.inject({
    method: 'PUT',
    url: '/api/users/me',
    headers: { authorization: `Bearer ${token}` },
    payload: { avatar_url: 'https://example.com/new-avatar.png' },
  })

  expect(res.statusCode).toBe(200)
  expect(res.json().avatar_url).toBe('https://example.com/new-avatar.png')

  // 旧本地文件应已被删除
  const files = await readdir(uploadsDir).catch(() => [])
  expect(files).not.toContain(oldFilename)
})

it('deletes old local avatar file when avatar_url is cleared', async () => {
  const uploadsDir = join(process.cwd(), 'uploads', 'avatars')
  await mkdir(uploadsDir, { recursive: true })

  // 模拟一个已存在的本地头像
  const oldFilename = `${1}-${Date.now()}.jpg`
  const oldFilepath = join(uploadsDir, oldFilename)
  const oldAvatarUrl = `/uploads/avatars/${oldFilename}`
  await writeFile(oldFilepath, Buffer.from('fake image'))

  // 将用户头像设为本地文件
  await app.pool.query('UPDATE users SET avatar_url = $1 WHERE username = $2', [
    oldAvatarUrl,
    'alice',
  ])

  // 清空头像
  const res = await app.inject({
    method: 'PUT',
    url: '/api/users/me',
    headers: { authorization: `Bearer ${token}` },
    payload: { avatar_url: '' },
  })

  expect(res.statusCode).toBe(200)
  expect(res.json().avatar_url).toBe('')

  // 旧本地文件应已被删除
  const files = await readdir(uploadsDir).catch(() => [])
  expect(files).not.toContain(oldFilename)
})
```

同时在文件顶部添加导入：
```typescript
import { mkdir, writeFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'
```

- [ ] **步骤 2：运行测试验证失败**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test -- users.test.ts
```

预期：FAIL — 旧文件未被删除

- [ ] **步骤 3：更新 users 路由以删除旧头像文件**

修改 `server/src/routes/users.ts`：

在顶部添加导入：
```typescript
import { rm } from 'node:fs/promises'
import { join } from 'node:path'
```

在导入之后添加常量：
```typescript
const UPLOADS_DIR = join(process.cwd(), 'uploads', 'avatars')
```

替换 `fastify.put('/me', ...)` 处理函数：

```typescript
fastify.put('/me', {
  schema: {
    body: {
      type: 'object',
      additionalProperties: false,
      properties: {
        display_name: { type: 'string', maxLength: 100 },
        avatar_url: { type: 'string', maxLength: 2048 },
      },
    },
  },
}, async (request, reply) => {
  const { display_name, avatar_url } = request.body as {
    display_name?: string
    avatar_url?: string
  }

  if (display_name === undefined && avatar_url === undefined) {
    return reply.status(400).send({ error: 'No fields to update' })
  }

  const trimmedDisplayName = display_name !== undefined ? display_name.trim() : undefined

  // 更新前获取旧头像 URL（用于清理）
  let oldAvatarUrl: string | null = null
  if (avatar_url !== undefined) {
    const oldResult = await fastify.pool.query(
      'SELECT avatar_url FROM users WHERE id = $1',
      [request.user.id],
    )
    if (oldResult.rowCount === 0) {
      return reply.status(401).send({ error: 'User no longer exists' })
    }
    oldAvatarUrl = oldResult.rows[0]?.avatar_url as string | null
  }

  const result = await fastify.pool.query(
    `UPDATE users
     SET display_name = COALESCE($1, display_name),
         avatar_url   = COALESCE($2, avatar_url)
     WHERE id = $3
     RETURNING id, username, email, display_name, avatar_url, created_at`,
    [trimmedDisplayName ?? null, avatar_url ?? null, request.user.id],
  )

  if (result.rowCount === 0) {
    return reply.status(401).send({ error: 'User no longer exists' })
  }

  // 如果 avatar_url 发生变更，清理旧的本地头像文件（尽力而为）
  if (
    avatar_url !== undefined &&
    oldAvatarUrl?.startsWith('/uploads/avatars/') &&
    oldAvatarUrl !== avatar_url
  ) {
    const oldFilename = oldAvatarUrl.split('/').pop()
    if (oldFilename) {
      await rm(join(UPLOADS_DIR, oldFilename), { force: true }).catch((err) => {
        fastify.log.warn({ err, oldFilename }, 'failed to cleanup old avatar file')
      })
    }
  }

  return reply.status(200).send(result.rows[0])
})
```

- [ ] **步骤 4：运行测试验证通过**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test -- users.test.ts
```

预期：PASS

- [ ] **步骤 5：运行完整测试套件**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm test
```

预期：全部通过

- [ ] **步骤 6：运行 lint**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm run lint
```

预期：无错误

- [ ] **步骤 7：提交**

```bash
git add server/src/routes/users.ts server/tests/users.test.ts
git commit -m "feat(server): clean up old local avatar file on profile update"
```

---

## 任务 7：创建前端图片压缩工具

**文件：**
- 新建：`client/src/lib/image.ts`

- [ ] **步骤 1：创建自适应质量的图片压缩工具**

新建 `client/src/lib/image.ts`：

```typescript
const MAX_DIMENSION = 800
const TARGET_SIZE_BYTES = 500 * 1024 // 500KB 目标
const MIN_QUALITY = 0.4
const MIN_DIMENSION = 200

export type ImageValidationError = 'INVALID_TYPE' | 'FILE_TOO_LARGE'

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp']
const MAX_INPUT_SIZE = 10 * 1024 * 1024 // 10MB

export function validateImageFile(file: File): ImageValidationError | null {
  if (!ALLOWED_TYPES.includes(file.type)) {
    return 'INVALID_TYPE'
  }

  if (file.size > MAX_INPUT_SIZE) {
    return 'FILE_TOO_LARGE'
  }

  return null
}

export async function compressImage(file: File): Promise<Blob> {
  const img = await createImageBitmap(file)

  let dimension = MAX_DIMENSION
  let quality = 0.85

  // 自适应压缩循环
  while (true) {
    const scale = Math.min(1, dimension / Math.max(img.width, img.height))
    const width = Math.round(img.width * scale)
    const height = Math.round(img.height * scale)

    const canvas = new OffscreenCanvas(width, height)
    const ctx = canvas.getContext('2d')
    if (!ctx) {
      throw new Error('Failed to get canvas context')
    }
    // 先铺白底再绘制图片（透明区域转 JPEG 时会变黑）
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, width, height)
    ctx.drawImage(img, 0, 0, width, height)

    const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality })

    // 达到目标大小或已到最低限制，返回
    if (
      blob.size <= TARGET_SIZE_BYTES ||
      (quality <= MIN_QUALITY && dimension <= MIN_DIMENSION)
    ) {
      return blob
    }

    // 先降质量，再降尺寸
    if (quality > MIN_QUALITY) {
      quality = Math.max(MIN_QUALITY, quality - 0.15)
    } else if (dimension > MIN_DIMENSION) {
      dimension = Math.max(MIN_DIMENSION, dimension - 200)
      quality = 0.7 // 为更小尺寸重置质量
    } else {
      // 不应到达此处，但仍返回
      return blob
    }
  }
}
```

- [ ] **步骤 2：运行 lint**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/client && npm run lint
```

预期：无错误

- [ ] **步骤 3：提交**

```bash
git add client/src/lib/image.ts
git commit -m "feat(client): add adaptive image compression utility"
```

---

## 任务 8：添加上传 API 函数

**文件：**
- 修改：`client/src/lib/api.ts`

- [ ] **步骤 1：添加 uploadAvatar 函数**

在 `client/src/lib/api.ts` 中添加：

```typescript
export async function uploadAvatar(blob: Blob): Promise<{ avatar_url: string }> {
  const token = localStorage.getItem('token')
  const formData = new FormData()
  formData.append('avatar', blob, 'avatar.jpg')

  const res = await fetch(`${API_BASE}/upload/avatar`, {
    method: 'POST',
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: formData,
  })

  if (!res.ok) {
    let message = 'Upload failed'
    try {
      const data = (await res.json()) as { error?: string }
      if (data.error) message = data.error
    } catch {
      // 非 JSON 错误响应体
    }
    throw new ApiError(message, res.status)
  }

  return (await res.json()) as { avatar_url: string }
}
```

- [ ] **步骤 2：运行 lint**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/client && npm run lint
```

预期：无错误

- [ ] **步骤 3：提交**

```bash
git add client/src/lib/api.ts
git commit -m "feat(client): add uploadAvatar API function"
```

---

## 任务 9：添加 i18n 字符串

**文件：**
- 修改：`client/src/locales/en.json`
- 修改：`client/src/locales/zh.json`

- [ ] **步骤 1：读取当前语言文件**

读取两个文件了解现有结构。

- [ ] **步骤 2：添加英文字符串**

在 `client/src/locales/en.json` 的 `profile` 部分添加：

```json
"selectFile": "Select Image",
"uploading": "Uploading...",
"compressing": "Compressing...",
"uploadSuccess": "Avatar uploaded",
"uploadFailed": "Upload failed",
"invalidFileType": "Invalid file type. Allowed: JPG, PNG, GIF, WebP",
"fileTooLarge": "File too large. Maximum: 10MB",
"uploadHint": "JPG, PNG, GIF, WebP · Max 10MB"
```

- [ ] **步骤 3：添加中文字符串**

在 `client/src/locales/zh.json` 的 `profile` 部分添加：

```json
"selectFile": "选择图片",
"uploading": "上传中...",
"compressing": "压缩中...",
"uploadSuccess": "头像已上传",
"uploadFailed": "上传失败",
"invalidFileType": "文件类型不支持，仅支持 JPG、PNG、GIF、WebP",
"fileTooLarge": "文件过大，最大 10MB",
"uploadHint": "支持 JPG、PNG、GIF、WebP，最大 10MB"
```

- [ ] **步骤 4：提交**

```bash
git add client/src/locales/en.json client/src/locales/zh.json
git commit -m "feat(client): add avatar upload i18n strings"
```

---

## 任务 10：更新 ProfileEditPage 上传 UI

**文件：**
- 修改：`client/src/pages/ProfileEditPage.tsx`
- 修改：`client/src/index.css`

- [ ] **步骤 1：更新 ProfileEditPage.tsx**

替换 `client/src/pages/ProfileEditPage.tsx` 内容：

```tsx
import { useState, useRef, type FormEvent, type ChangeEvent } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { ArrowLeft, Upload } from 'lucide-react'
import { toast } from 'sonner'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth'
import { uploadAvatar, ApiError } from '@/lib/api'
import { compressImage, validateImageFile } from '@/lib/image'

export function ProfileEditPage() {
  const { user, updateProfile, fetchMe, logout } = useAuthStore()
  const { t } = useTranslation()
  const navigate = useNavigate()
  const location = useLocation()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [displayName, setDisplayName] = useState(user?.display_name ?? '')
  const [avatarUrl, setAvatarUrl] = useState(user?.avatar_url ?? '')
  const [loading, setLoading] = useState(false)
  const [uploadStatus, setUploadStatus] = useState<'idle' | 'compressing' | 'uploading'>('idle')

  const initials = (user?.display_name || user?.username || '').slice(0, 2).toUpperCase()

  const handleFileChange = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    // 校验文件
    const validationError = validateImageFile(file)
    if (validationError) {
      const errorKey =
        validationError === 'INVALID_TYPE' ? 'profile.invalidFileType' : 'profile.fileTooLarge'
      toast.error(t(errorKey))
      if (fileInputRef.current) fileInputRef.current.value = ''
      return
    }

    try {
      // 压缩（Canvas API 不可用时降级为直传原文件）
      setUploadStatus('compressing')
      let blob: Blob
      try {
        blob = await compressImage(file)
      } catch {
        blob = file
      }

      // 上传
      setUploadStatus('uploading')
      const result = await uploadAvatar(blob)

      // 更新本地状态并重新获取用户信息
      setAvatarUrl(result.avatar_url)
      await fetchMe()
      toast.success(t('profile.uploadSuccess'))
    } catch (err) {
      // 处理 401 — 用户不存在，退出登录
      if (err instanceof ApiError && err.status === 401) {
        logout()
      }
      toast.error(err instanceof Error ? err.message : t('profile.uploadFailed'))
    } finally {
      setUploadStatus('idle')
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await updateProfile({
        display_name: displayName,
        avatar_url: avatarUrl,
      })
      toast.success(t('profile.updated'))
      navigate({
        pathname: '/',
        search: location.search,
      })
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t('profile.failed'))
    } finally {
      setLoading(false)
    }
  }

  const isUploading = uploadStatus !== 'idle'
  const uploadButtonText =
    uploadStatus === 'compressing'
      ? t('profile.compressing')
      : uploadStatus === 'uploading'
        ? t('profile.uploading')
        : t('profile.selectFile')

  return (
    <div className="echo-profile-page">
      <div className="echo-profile-card">
        <button
          onClick={() =>
            navigate({
              pathname: '/',
              search: location.search,
            })
          }
          className="echo-profile-back"
        >
          <ArrowLeft size={18} />
          <span>{t('profile.back')}</span>
        </button>

        <h1 className="echo-profile-heading">{t('profile.heading')}</h1>

        {/* 头像上传区域 */}
        <div className="echo-profile-avatar-section">
          <div className="echo-profile-avatar-preview">
            {avatarUrl ? <img src={avatarUrl} alt="" /> : initials}
          </div>

          <input
            ref={fileInputRef}
            type="file"
            accept="image/jpeg,image/png,image/gif,image/webp"
            onChange={handleFileChange}
            className="echo-profile-file-input"
            disabled={isUploading}
          />

          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            disabled={isUploading}
            className="echo-profile-upload-btn"
          >
            <Upload size={16} />
            <span>{uploadButtonText}</span>
          </button>

          <p className="echo-profile-upload-hint">{t('profile.uploadHint')}</p>
        </div>

        <form onSubmit={handleSubmit} className="echo-profile-form">
          <div className="auth-field">
            <label htmlFor="displayName" className="echo-profile-label">
              {t('profile.displayName')}
            </label>
            <input
              id="displayName"
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              className="echo-profile-input"
              placeholder={user?.username}
            />
          </div>

          <div className="auth-field">
            <label htmlFor="avatarUrl" className="echo-profile-label">
              {t('profile.avatarUrl')}
            </label>
            <input
              id="avatarUrl"
              type="url"
              value={avatarUrl}
              onChange={(e) => setAvatarUrl(e.target.value)}
              className="echo-profile-input"
              placeholder="https://example.com/avatar.jpg"
            />
          </div>

          <button
            type="submit"
            disabled={loading || isUploading}
            className="echo-profile-submit"
          >
            {loading ? t('profile.saving') : t('profile.save')}
          </button>
        </form>
      </div>
    </div>
  )
}
```

- [ ] **步骤 2：在 index.css 中添加 CSS 样式**

在已有的 `.echo-profile-avatar-preview img` 样式之后添加：

```css
.echo-profile-avatar-section {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 1.5rem;
}

.echo-profile-file-input {
  display: none;
}

.echo-profile-upload-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 1rem;
  background: var(--echo-glass-bg);
  border: 1px solid var(--echo-glass-border);
  border-radius: 0.5rem;
  color: var(--echo-text);
  font-size: 0.875rem;
  cursor: pointer;
  transition: background 0.15s, border-color 0.15s;
  backdrop-filter: blur(var(--echo-glass-blur));
}

.echo-profile-upload-btn:hover:not(:disabled) {
  background: var(--echo-glass-bg-heavy);
  border-color: var(--echo-accent);
}

.echo-profile-upload-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.echo-profile-upload-hint {
  font-size: 0.75rem;
  color: var(--echo-text);
  opacity: 0.6;
  margin: 0;
}
```

- [ ] **步骤 3：运行 lint**

执行：
```bash
cd /Users/xuyuqin/Documents/EchoIM/client && npm run lint
```

预期：无错误

- [ ] **步骤 4：提交**

```bash
git add client/src/pages/ProfileEditPage.tsx client/src/index.css
git commit -m "feat(client): add avatar upload UI to ProfileEditPage"
```

---

## 任务 11：手动集成测试

- [ ] **步骤 1：启动数据库和 Redis**

```bash
cd /Users/xuyuqin/Documents/EchoIM && docker compose up postgres redis
```

- [ ] **步骤 2：启动后端**

新终端：
```bash
cd /Users/xuyuqin/Documents/EchoIM/server && npm run dev
```

- [ ] **步骤 3：启动前端**

新终端：
```bash
cd /Users/xuyuqin/Documents/EchoIM/client && npm run dev
```

注意：`vite.config.ts` 默认 `ECHOIM_API_ORIGIN` 为 `http://localhost:3000`，前端会代理到本地后端。

- [ ] **步骤 4：测试正常流程**

1. 打开 http://localhost:5173
2. 登录或注册
3. 进入资料编辑页
4. 点击「选择图片」并选择一个合法图片（JPG/PNG/GIF/WebP）
5. 验证状态依次显示「压缩中...」→「上传中...」
6. 验证 toast 显示成功消息（对应当前语言）
7. 验证头像预览立即更新
8. 点击保存
9. 刷新页面 — 验证头像持久化

- [ ] **步骤 5：测试 /uploads 代理**

1. 上传后，从浏览器开发者工具复制头像 URL（如 `/uploads/avatars/1-1234567890.jpg`）
2. 在新标签页打开：`http://localhost:5173/uploads/avatars/1-1234567890.jpg`
3. 验证图片正常加载

- [ ] **步骤 6：测试错误场景**

1. 尝试上传 `.txt` 文件 — 应显示本地化的「文件类型不支持」错误
2. 尝试上传 >10MB 的文件 — 应显示本地化的「文件过大」错误
3. 验证 URL 输入仍然可用（输入外部 URL，保存，验证持久化）

- [ ] **步骤 7：测试通过上传替换头像**

1. 上传头像 A
2. 在 Network 面板或 `server/uploads/avatars/` 中记录文件名
3. 上传头像 B
4. 检查 `server/uploads/avatars/` — 旧文件应已被删除

- [ ] **步骤 8：测试通过 URL 变更清理头像**

1. 上传本地头像
2. 记录文件名
3. 编辑资料，将 avatar_url 改为外部 URL（如 `https://example.com/avatar.png`）
4. 点击保存
5. 检查 `server/uploads/avatars/` — 旧本地文件应已被删除

- [ ] **步骤 9：测试通过清空清理头像**

1. 上传本地头像
2. 记录文件名
3. 编辑资料，清空 avatar_url（空字符串）
4. 点击保存
5. 检查 `server/uploads/avatars/` — 旧本地文件应已被删除

- [ ] **步骤 10：测试多实例（可选）**

**重要：** 先停止本地 dev server（在运行 `npm run dev` 的终端 2 中按 Ctrl+C）。

1. 启动多实例后端：
```bash
cd /Users/xuyuqin/Documents/EchoIM && docker compose --profile multi up --build
```

2. 保持前端在 5173 端口运行。如已停止，指定 API 目标重启：
```bash
cd /Users/xuyuqin/Documents/EchoIM/client && ECHOIM_API_ORIGIN=http://localhost:3000 npm run dev
```

3. 打开 http://localhost:5173（前端，代理到 3000 端口的 nginx）
4. 上传头像
5. 多次刷新（nginx 会在 server-1 和 server-2 之间轮询）
6. 头像应始终正确加载（共享卷生效）

---

## 总结

| 任务 | 描述 | 关键文件 |
|------|------|----------|
| 1 | 安装依赖 | package.json |
| 2 | 上传目录 + Docker 卷 | .gitkeep, docker-compose.yml |
| 3 | /uploads 代理 | vite.config.ts, nginx.conf |
| 4 | 静态文件插件 | plugins/static.ts |
| 5 | 上传路由 + sharp | routes/upload.ts |
| 6 | Users 路由头像清理 | routes/users.ts |
| 7 | 前端压缩 | lib/image.ts |
| 8 | 上传 API 函数 | lib/api.ts |
| 9 | i18n 字符串 | locales/*.json |
| 10 | ProfileEditPage UI | ProfileEditPage.tsx, index.css |
| 11 | 集成测试 | 手动验证 |

**总提交数：** 11

---

## 相对 v3 的变更

| 问题 | 修复 |
|------|------|
| 多实例测试不可达 | 任务 11：前端保持在 5173，代理到 3000 的 nginx |
| uploadAvatar 绕过 401 登出 | 任务 10：检查 ApiError.status === 401，调用 logout() |
| 数据库出错留下孤儿文件 | 任务 5：writeFile + UPDATE 外包 try-catch，出错时清理 |
| 文件清理失败 = 500 | 任务 5 & 6：尽力而为 `await rm().catch(log)` |
| 「未提供文件」测试 | 任务 5：使用空 multipart 表单而非缺少 header |
| 重复 useAuthStore 导入 | 任务 10：将 logout 加入现有解构 |
| 透明 PNG/WebP 变黑底 | 任务 5 & 7：sharp `.flatten()` 铺白底 + Canvas `fillRect` 白色 |
| 校验失败后 file input 未清空 | 任务 10：validation return 前清空 `fileInputRef` |
| 前端压缩 API 不可用时崩溃 | 任务 10：compressImage 外包 try-catch，降级直传原文件 |
