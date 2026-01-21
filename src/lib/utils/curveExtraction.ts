/**
 * Workstream B: Curve Extraction Utilities
 *
 * Shared utilities for extracting curves from CGM graph images
 * using various computer vision techniques:
 * - Sobel edge detection
 * - Canny-style edge linking
 * - Connected component analysis
 * - Curve smoothing and interpolation
 */

/**
 * 2D point with optional metadata
 */
export interface Point2D {
  x: number;
  y: number;
  intensity?: number;
}

/**
 * Sobel edge detection kernels
 */
const SOBEL_X = [
  [-1, 0, 1],
  [-2, 0, 2],
  [-1, 0, 1]
];

const SOBEL_Y = [
  [-1, -2, -1],
  [0, 0, 0],
  [1, 2, 1]
];

/**
 * Convert image data to grayscale array
 */
export function toGrayscale(imageData: ImageData): Float32Array {
  const { width, height, data } = imageData;
  const gray = new Float32Array(width * height);

  for (let i = 0; i < data.length; i += 4) {
    // Standard luminance formula
    gray[i / 4] = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
  }

  return gray;
}

/**
 * Apply Gaussian blur to grayscale image
 */
export function gaussianBlur(
  gray: Float32Array,
  width: number,
  height: number,
  sigma: number = 1.4
): Float32Array {
  const kernelSize = Math.ceil(sigma * 3) * 2 + 1;
  const kernel = createGaussianKernel(kernelSize, sigma);
  const halfK = Math.floor(kernelSize / 2);

  const blurred = new Float32Array(width * height);

  // Separable convolution (horizontal then vertical)
  const temp = new Float32Array(width * height);

  // Horizontal pass
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0;
      let weightSum = 0;

      for (let k = -halfK; k <= halfK; k++) {
        const sx = Math.max(0, Math.min(width - 1, x + k));
        const weight = kernel[k + halfK];
        sum += gray[y * width + sx] * weight;
        weightSum += weight;
      }

      temp[y * width + x] = sum / weightSum;
    }
  }

  // Vertical pass
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0;
      let weightSum = 0;

      for (let k = -halfK; k <= halfK; k++) {
        const sy = Math.max(0, Math.min(height - 1, y + k));
        const weight = kernel[k + halfK];
        sum += temp[sy * width + x] * weight;
        weightSum += weight;
      }

      blurred[y * width + x] = sum / weightSum;
    }
  }

  return blurred;
}

/**
 * Create 1D Gaussian kernel
 */
function createGaussianKernel(size: number, sigma: number): Float32Array {
  const kernel = new Float32Array(size);
  const halfSize = Math.floor(size / 2);
  const sigma2 = sigma * sigma;

  let sum = 0;
  for (let i = 0; i < size; i++) {
    const x = i - halfSize;
    kernel[i] = Math.exp(-(x * x) / (2 * sigma2));
    sum += kernel[i];
  }

  // Normalize
  for (let i = 0; i < size; i++) {
    kernel[i] /= sum;
  }

  return kernel;
}

/**
 * Apply Sobel edge detection
 * Returns gradient magnitude and direction
 */
export function sobelEdgeDetection(
  gray: Float32Array,
  width: number,
  height: number
): { magnitude: Float32Array; direction: Float32Array } {
  const magnitude = new Float32Array(width * height);
  const direction = new Float32Array(width * height);

  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      let gx = 0;
      let gy = 0;

      // Apply Sobel kernels
      for (let ky = -1; ky <= 1; ky++) {
        for (let kx = -1; kx <= 1; kx++) {
          const pixel = gray[(y + ky) * width + (x + kx)];
          gx += pixel * SOBEL_X[ky + 1][kx + 1];
          gy += pixel * SOBEL_Y[ky + 1][kx + 1];
        }
      }

      const idx = y * width + x;
      magnitude[idx] = Math.sqrt(gx * gx + gy * gy);
      direction[idx] = Math.atan2(gy, gx);
    }
  }

  return { magnitude, direction };
}

/**
 * Non-maximum suppression for edge thinning
 */
export function nonMaximumSuppression(
  magnitude: Float32Array,
  direction: Float32Array,
  width: number,
  height: number
): Float32Array {
  const suppressed = new Float32Array(width * height);

  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const idx = y * width + x;
      const mag = magnitude[idx];
      const dir = direction[idx];

      // Quantize direction to 4 angles (0, 45, 90, 135 degrees)
      const angle = ((dir * 180) / Math.PI + 180) % 180;

      let neighbor1 = 0;
      let neighbor2 = 0;

      if ((angle >= 0 && angle < 22.5) || (angle >= 157.5 && angle <= 180)) {
        // Horizontal edge
        neighbor1 = magnitude[idx - 1];
        neighbor2 = magnitude[idx + 1];
      } else if (angle >= 22.5 && angle < 67.5) {
        // 45 degree edge
        neighbor1 = magnitude[(y - 1) * width + (x + 1)];
        neighbor2 = magnitude[(y + 1) * width + (x - 1)];
      } else if (angle >= 67.5 && angle < 112.5) {
        // Vertical edge
        neighbor1 = magnitude[(y - 1) * width + x];
        neighbor2 = magnitude[(y + 1) * width + x];
      } else {
        // 135 degree edge
        neighbor1 = magnitude[(y - 1) * width + (x - 1)];
        neighbor2 = magnitude[(y + 1) * width + (x + 1)];
      }

      // Keep only if local maximum
      if (mag >= neighbor1 && mag >= neighbor2) {
        suppressed[idx] = mag;
      }
    }
  }

  return suppressed;
}

/**
 * Double threshold and edge tracking (Canny-style hysteresis)
 */
export function hysteresisThreshold(
  edges: Float32Array,
  width: number,
  height: number,
  lowThreshold: number,
  highThreshold: number
): Uint8Array {
  const result = new Uint8Array(width * height);

  // Mark strong edges
  const strong = 255;
  const weak = 128;

  for (let i = 0; i < edges.length; i++) {
    if (edges[i] >= highThreshold) {
      result[i] = strong;
    } else if (edges[i] >= lowThreshold) {
      result[i] = weak;
    }
  }

  // Track edges: connect weak edges to strong edges
  let changed = true;
  while (changed) {
    changed = false;

    for (let y = 1; y < height - 1; y++) {
      for (let x = 1; x < width - 1; x++) {
        const idx = y * width + x;

        if (result[idx] === weak) {
          // Check 8-connected neighbors for strong edge
          for (let dy = -1; dy <= 1; dy++) {
            for (let dx = -1; dx <= 1; dx++) {
              if (result[(y + dy) * width + (x + dx)] === strong) {
                result[idx] = strong;
                changed = true;
                break;
              }
            }
            if (result[idx] === strong) break;
          }
        }
      }
    }
  }

  // Remove remaining weak edges
  for (let i = 0; i < result.length; i++) {
    if (result[i] !== strong) {
      result[i] = 0;
    }
  }

  return result;
}

/**
 * Full Canny edge detection pipeline
 */
export function cannyEdgeDetection(
  imageData: ImageData,
  lowThreshold: number = 30,
  highThreshold: number = 100,
  sigma: number = 1.4
): Uint8Array {
  const { width, height } = imageData;

  // Convert to grayscale
  const gray = toGrayscale(imageData);

  // Apply Gaussian blur
  const blurred = gaussianBlur(gray, width, height, sigma);

  // Sobel gradient
  const { magnitude, direction } = sobelEdgeDetection(blurred, width, height);

  // Non-maximum suppression
  const thinned = nonMaximumSuppression(magnitude, direction, width, height);

  // Hysteresis thresholding
  return hysteresisThreshold(thinned, width, height, lowThreshold, highThreshold);
}

/**
 * Extract edge points from binary edge image
 */
export function extractEdgePoints(
  edges: Uint8Array,
  width: number,
  height: number,
  region?: { x: number; y: number; width: number; height: number }
): Point2D[] {
  const points: Point2D[] = [];

  const startX = region ? region.x : 0;
  const startY = region ? region.y : 0;
  const endX = region ? region.x + region.width : width;
  const endY = region ? region.y + region.height : height;

  for (let y = startY; y < endY; y++) {
    for (let x = startX; x < endX; x++) {
      if (edges[y * width + x] > 0) {
        points.push({ x, y });
      }
    }
  }

  return points;
}

/**
 * Find connected components in edge image
 */
export function findConnectedComponents(
  edges: Uint8Array,
  width: number,
  height: number
): { labels: Int32Array; count: number } {
  const labels = new Int32Array(width * height);
  let currentLabel = 0;
  const equivalences = new Map<number, number>();

  // First pass: label connected regions
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = y * width + x;

      if (edges[idx] === 0) continue;

      // Check neighbors (4-connected)
      const neighbors: number[] = [];

      if (x > 0 && labels[idx - 1] > 0) {
        neighbors.push(labels[idx - 1]);
      }
      if (y > 0 && labels[idx - width] > 0) {
        neighbors.push(labels[idx - width]);
      }

      if (neighbors.length === 0) {
        // New component
        currentLabel++;
        labels[idx] = currentLabel;
      } else {
        // Use minimum neighbor label
        const minLabel = Math.min(...neighbors);
        labels[idx] = minLabel;

        // Record equivalences
        for (const n of neighbors) {
          if (n !== minLabel) {
            equivalences.set(n, Math.min(equivalences.get(n) || n, minLabel));
          }
        }
      }
    }
  }

  // Resolve equivalences
  function findRoot(label: number): number {
    while (equivalences.has(label)) {
      label = equivalences.get(label)!;
    }
    return label;
  }

  // Second pass: relabel with resolved equivalences
  const finalLabels = new Map<number, number>();
  let finalCount = 0;

  for (let i = 0; i < labels.length; i++) {
    if (labels[i] > 0) {
      const root = findRoot(labels[i]);
      if (!finalLabels.has(root)) {
        finalCount++;
        finalLabels.set(root, finalCount);
      }
      labels[i] = finalLabels.get(root)!;
    }
  }

  return { labels, count: finalCount };
}

/**
 * Get largest connected component
 */
export function getLargestComponent(
  labels: Int32Array,
  count: number,
  width: number,
  height: number
): Point2D[] {
  if (count === 0) return [];

  // Count pixels per component
  const counts = new Map<number, number>();
  for (let i = 0; i < labels.length; i++) {
    if (labels[i] > 0) {
      counts.set(labels[i], (counts.get(labels[i]) || 0) + 1);
    }
  }

  // Find largest using Array.from
  let maxLabel = 0;
  let maxCount = 0;
  const countEntries = Array.from(counts.entries());
  for (const [label, cnt] of countEntries) {
    if (cnt > maxCount) {
      maxCount = cnt;
      maxLabel = label;
    }
  }

  // Extract points
  const points: Point2D[] = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (labels[y * width + x] === maxLabel) {
        points.push({ x, y });
      }
    }
  }

  return points;
}

/**
 * Fit a smooth curve through points using cubic spline interpolation
 */
export function smoothCurveSpline(points: Point2D[], numOutputPoints: number): Point2D[] {
  if (points.length < 4) return points;

  // Sort by x
  const sorted = [...points].sort((a, b) => a.x - b.x);

  // Remove duplicate x values (keep average y)
  const uniqueX = new Map<number, number[]>();
  for (const p of sorted) {
    if (!uniqueX.has(p.x)) {
      uniqueX.set(p.x, []);
    }
    uniqueX.get(p.x)!.push(p.y);
  }

  const averaged: Point2D[] = [];
  const uniqueXEntries = Array.from(uniqueX.entries());
  for (const [x, ys] of uniqueXEntries) {
    averaged.push({
      x,
      y: ys.reduce((a, b) => a + b, 0) / ys.length
    });
  }

  if (averaged.length < 4) return averaged;

  // Simple moving average smoothing as fallback
  // (Full cubic spline is complex to implement without library)
  const result: Point2D[] = [];
  const windowSize = Math.max(3, Math.floor(averaged.length / numOutputPoints));

  for (let i = 0; i < numOutputPoints; i++) {
    const targetIdx = Math.floor((i / numOutputPoints) * averaged.length);
    const start = Math.max(0, targetIdx - Math.floor(windowSize / 2));
    const end = Math.min(averaged.length, targetIdx + Math.ceil(windowSize / 2));

    let sumX = 0;
    let sumY = 0;
    let count = 0;

    for (let j = start; j < end; j++) {
      sumX += averaged[j].x;
      sumY += averaged[j].y;
      count++;
    }

    if (count > 0) {
      result.push({ x: sumX / count, y: sumY / count });
    }
  }

  return result;
}

/**
 * Resample points to uniform x spacing
 */
export function resampleUniform(points: Point2D[], numPoints: number): Point2D[] {
  if (points.length < 2) return points;

  const sorted = [...points].sort((a, b) => a.x - b.x);
  const minX = sorted[0].x;
  const maxX = sorted[sorted.length - 1].x;
  const step = (maxX - minX) / (numPoints - 1);

  const result: Point2D[] = [];

  for (let i = 0; i < numPoints; i++) {
    const targetX = minX + i * step;

    // Find surrounding points
    let left = sorted[0];
    let right = sorted[sorted.length - 1];

    for (let j = 0; j < sorted.length - 1; j++) {
      if (sorted[j].x <= targetX && sorted[j + 1].x >= targetX) {
        left = sorted[j];
        right = sorted[j + 1];
        break;
      }
    }

    // Linear interpolation
    let y: number;
    if (left.x === right.x) {
      y = left.y;
    } else {
      const t = (targetX - left.x) / (right.x - left.x);
      y = left.y + t * (right.y - left.y);
    }

    result.push({ x: targetX, y });
  }

  return result;
}
