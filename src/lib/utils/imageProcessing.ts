/**
 * Image Processing Utilities
 * Workstream A: AI-Powered Food Recognition
 *
 * Handles image compression, orientation, and format conversion
 * for optimal API submission.
 */

export interface ImageProcessingOptions {
  maxWidth?: number;
  maxHeight?: number;
  quality?: number;
  format?: 'image/jpeg' | 'image/webp' | 'image/png';
}

const DEFAULT_OPTIONS: Required<ImageProcessingOptions> = {
  maxWidth: 1024,
  maxHeight: 1024,
  quality: 0.8,
  format: 'image/jpeg'
};

/**
 * Compresses and resizes an image blob for API submission
 */
export async function compressImage(
  blob: Blob,
  options: ImageProcessingOptions = {}
): Promise<Blob> {
  const opts = { ...DEFAULT_OPTIONS, ...options };

  // Create image element
  const img = await createImageFromBlob(blob);

  // Calculate new dimensions maintaining aspect ratio
  const { width, height } = calculateDimensions(
    img.width,
    img.height,
    opts.maxWidth,
    opts.maxHeight
  );

  // Create canvas and draw resized image
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;

  const ctx = canvas.getContext('2d');
  if (!ctx) {
    throw new Error('Failed to get canvas context');
  }

  // Handle EXIF orientation
  const orientation = await getExifOrientation(blob);
  applyExifOrientation(ctx, orientation, width, height);

  ctx.drawImage(img, 0, 0, width, height);

  // Convert to blob
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (result) => {
        if (result) {
          resolve(result);
        } else {
          reject(new Error('Failed to compress image'));
        }
      },
      opts.format,
      opts.quality
    );
  });
}

/**
 * Creates an HTMLImageElement from a Blob
 */
export function createImageFromBlob(blob: Blob): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(blob);

    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };

    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('Failed to load image'));
    };

    img.src = url;
  });
}

/**
 * Calculates resized dimensions while maintaining aspect ratio
 */
function calculateDimensions(
  originalWidth: number,
  originalHeight: number,
  maxWidth: number,
  maxHeight: number
): { width: number; height: number } {
  let width = originalWidth;
  let height = originalHeight;

  if (width > maxWidth) {
    height = (height * maxWidth) / width;
    width = maxWidth;
  }

  if (height > maxHeight) {
    width = (width * maxHeight) / height;
    height = maxHeight;
  }

  return { width: Math.round(width), height: Math.round(height) };
}

/**
 * Reads EXIF orientation from image blob
 * Returns orientation value 1-8 (1 = normal)
 */
async function getExifOrientation(blob: Blob): Promise<number> {
  try {
    const buffer = await blob.slice(0, 65536).arrayBuffer();
    const view = new DataView(buffer);

    // Check for JPEG
    if (view.getUint16(0, false) !== 0xffd8) {
      return 1;
    }

    let offset = 2;
    while (offset < view.byteLength) {
      if (view.getUint16(offset, false) === 0xffe1) {
        // APP1 marker
        const length = view.getUint16(offset + 2, false);

        // Check for Exif
        if (
          view.getUint32(offset + 4, false) === 0x45786966 &&
          view.getUint16(offset + 8, false) === 0x0000
        ) {
          const tiffOffset = offset + 10;
          const littleEndian = view.getUint16(tiffOffset, false) === 0x4949;
          const ifdOffset = view.getUint32(tiffOffset + 4, littleEndian);
          const tags = view.getUint16(tiffOffset + ifdOffset, littleEndian);

          for (let i = 0; i < tags; i++) {
            const tagOffset = tiffOffset + ifdOffset + 2 + i * 12;
            if (view.getUint16(tagOffset, littleEndian) === 0x0112) {
              return view.getUint16(tagOffset + 8, littleEndian);
            }
          }
        }

        offset += 2 + length;
      } else if ((view.getUint16(offset, false) & 0xff00) !== 0xff00) {
        break;
      } else {
        offset += 2 + view.getUint16(offset + 2, false);
      }
    }
  } catch {
    // Ignore EXIF parsing errors
  }

  return 1;
}

/**
 * Applies EXIF orientation transformations to canvas context
 */
function applyExifOrientation(
  ctx: CanvasRenderingContext2D,
  orientation: number,
  width: number,
  height: number
): void {
  switch (orientation) {
    case 2:
      ctx.transform(-1, 0, 0, 1, width, 0);
      break;
    case 3:
      ctx.transform(-1, 0, 0, -1, width, height);
      break;
    case 4:
      ctx.transform(1, 0, 0, -1, 0, height);
      break;
    case 5:
      ctx.transform(0, 1, 1, 0, 0, 0);
      break;
    case 6:
      ctx.transform(0, 1, -1, 0, height, 0);
      break;
    case 7:
      ctx.transform(0, -1, -1, 0, height, width);
      break;
    case 8:
      ctx.transform(0, -1, 1, 0, 0, width);
      break;
  }
}

/**
 * Converts a data URL to a Blob
 */
export function dataUrlToBlob(dataUrl: string): Blob {
  const parts = dataUrl.split(',');
  const mimeMatch = parts[0].match(/:(.*?);/);
  const mime = mimeMatch ? mimeMatch[1] : 'image/jpeg';
  const base64 = atob(parts[1]);
  const array = new Uint8Array(base64.length);

  for (let i = 0; i < base64.length; i++) {
    array[i] = base64.charCodeAt(i);
  }

  return new Blob([array], { type: mime });
}

/**
 * Converts a Blob to a data URL
 */
export function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result as string);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

/**
 * Gets image dimensions from a Blob
 */
export async function getImageDimensions(blob: Blob): Promise<{ width: number; height: number }> {
  const img = await createImageFromBlob(blob);
  return { width: img.width, height: img.height };
}

/**
 * Checks if a file is a valid image type
 */
export function isValidImageType(file: File): boolean {
  const validTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
  return validTypes.includes(file.type);
}

/**
 * Gets the file size in a human-readable format
 */
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
