const MAX_DIMENSION = 800
const TARGET_SIZE_BYTES = 500 * 1024 // 500KB target
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
    ctx.drawImage(img, 0, 0, width, height)

    const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality })

    // If within target size or we've hit minimum limits, return
    if (
      blob.size <= TARGET_SIZE_BYTES ||
      (quality <= MIN_QUALITY && dimension <= MIN_DIMENSION)
    ) {
      return blob
    }

    // First reduce quality, then reduce dimension
    if (quality > MIN_QUALITY) {
      quality = Math.max(MIN_QUALITY, quality - 0.15)
    } else if (dimension > MIN_DIMENSION) {
      dimension = Math.max(MIN_DIMENSION, dimension - 200)
      quality = 0.7 // Reset quality for smaller dimension
    } else {
      // Shouldn't reach here, but return anyway
      return blob
    }
  }
}
