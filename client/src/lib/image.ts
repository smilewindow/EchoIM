export type ImageValidationError = 'INVALID_TYPE' | 'FILE_TOO_LARGE'

export interface CompressOptions {
  maxDimension?: number // default: 800
  targetSizeBytes?: number // default: 500 * 1024
  minDimension?: number // default: 200
  minQuality?: number // default: 0.4
}

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

export async function compressImage(file: File, opts?: CompressOptions): Promise<Blob> {
  const {
    maxDimension = 800,
    targetSizeBytes = 500 * 1024,
    minDimension = 200,
    minQuality = 0.4,
  } = opts ?? {}

  const img = await createImageBitmap(file)

  let dimension = maxDimension
  let quality = 0.85

  // Adaptive compression loop
  while (true) {
    const scale = Math.min(1, dimension / Math.max(img.width, img.height))
    const width = Math.round(img.width * scale)
    const height = Math.round(img.height * scale)

    const canvas = new OffscreenCanvas(width, height)
    const ctx = canvas.getContext('2d')
    if (!ctx) {
      throw new Error('Failed to get canvas context')
    }
    // Fill white background before drawing (transparent areas become black in JPEG)
    ctx.fillStyle = '#ffffff'
    ctx.fillRect(0, 0, width, height)
    ctx.drawImage(img, 0, 0, width, height)

    const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality })

    // If within target size or we've hit minimum limits, return
    if (
      blob.size <= targetSizeBytes ||
      (quality <= minQuality && dimension <= minDimension)
    ) {
      return blob
    }

    // First reduce quality, then reduce dimension
    if (quality > minQuality) {
      quality = Math.max(minQuality, quality - 0.15)
    } else if (dimension > minDimension) {
      dimension = Math.max(minDimension, dimension - 200)
      quality = 0.7 // Reset quality for smaller dimension
    } else {
      // Shouldn't reach here, but return anyway
      return blob
    }
  }
}
