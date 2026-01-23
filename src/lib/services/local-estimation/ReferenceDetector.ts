/**
 * Workstream C: Reference Object Detector
 * Detects credit cards and coins in images to establish scale (pixels per mm).
 * All processing happens locally using Canvas API.
 */

import type { DetectedReference, ReferenceObjectType } from '$lib/types/local-estimation';
import { REFERENCE_DIMENSIONS } from '$lib/types/local-estimation';

/**
 * Edge detection result
 */
interface EdgeData {
  data: Uint8ClampedArray;
  width: number;
  height: number;
}

/**
 * Contour (connected edge points)
 */
interface Contour {
  points: Array<{ x: number; y: number }>;
  boundingBox: { x: number; y: number; width: number; height: number };
  area: number;
}

/**
 * Rectangle candidate from contour analysis
 */
interface RectangleCandidate {
  corners: [
    { x: number; y: number },
    { x: number; y: number },
    { x: number; y: number },
    { x: number; y: number }
  ];
  width: number;
  height: number;
  aspectRatio: number;
  area: number;
  confidence: number;
}

/**
 * ReferenceDetector finds credit cards or coins in images to establish scale.
 * Uses edge detection and contour analysis (no external libraries).
 */
export class ReferenceDetector {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;

  constructor() {
    this.canvas = document.createElement('canvas');
    const ctx = this.canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) {
      throw new Error('Could not create canvas context');
    }
    this.ctx = ctx;
  }

  /**
   * Detect a reference object in the image.
   * Tries credit card first, then coins.
   */
  async detect(imageBlob: Blob): Promise<DetectedReference | null> {
    const image = await this.loadImage(imageBlob);

    // Scale down for processing if needed (performance)
    const maxDim = 800;
    const scale = Math.min(1, maxDim / Math.max(image.width, image.height));
    const width = Math.round(image.width * scale);
    const height = Math.round(image.height * scale);

    this.canvas.width = width;
    this.canvas.height = height;
    this.ctx.drawImage(image, 0, 0, width, height);

    // Get image data
    const imageData = this.ctx.getImageData(0, 0, width, height);

    // Try to detect credit card (most common reference)
    const cardResult = this.detectCreditCard(imageData, scale);
    if (cardResult && cardResult.confidence > 0.5) {
      return cardResult;
    }

    // Try to detect coins
    const coinResult = this.detectCoin(imageData, scale);
    if (coinResult && coinResult.confidence > 0.4) {
      return coinResult;
    }

    // Return card result even with lower confidence if available
    if (cardResult) {
      return cardResult;
    }

    return null;
  }

  /**
   * Detect credit card based on aspect ratio and size
   */
  private detectCreditCard(imageData: ImageData, scale: number): DetectedReference | null {
    // Credit card aspect ratio: 85.6 / 53.98 ≈ 1.586
    const targetAspectRatio = 85.6 / 53.98;
    const aspectTolerance = 0.15;

    // Apply edge detection
    const edges = this.sobelEdgeDetection(imageData);

    // Find contours
    const contours = this.findContours(edges);

    // Find rectangle candidates
    const rectangles = this.findRectangles(contours, imageData.width, imageData.height);

    // Filter for credit card aspect ratio
    const cardCandidates = rectangles.filter((rect) => {
      const aspectDiff = Math.abs(rect.aspectRatio - targetAspectRatio) / targetAspectRatio;
      return aspectDiff < aspectTolerance;
    });

    if (cardCandidates.length === 0) {
      return null;
    }

    // Score candidates (prefer larger, more rectangular shapes)
    const scored = cardCandidates.map((rect) => {
      const sizeScore = Math.min(1, rect.area / (imageData.width * imageData.height * 0.1));
      const aspectScore = 1 - Math.abs(rect.aspectRatio - targetAspectRatio) / targetAspectRatio;
      return {
        rect,
        score: sizeScore * 0.4 + aspectScore * 0.4 + rect.confidence * 0.2
      };
    });

    scored.sort((a, b) => b.score - a.score);
    const best = scored[0];

    // Scale corners back to original image coordinates
    const scaledCorners = best.rect.corners.map((c) => ({
      x: c.x / scale,
      y: c.y / scale
    })) as [
      { x: number; y: number },
      { x: number; y: number },
      { x: number; y: number },
      { x: number; y: number }
    ];

    // Calculate pixels per mm
    const cardDimensions = REFERENCE_DIMENSIONS['credit-card'];
    const detectedWidthPx = best.rect.width / scale;
    const pixelsPerMm = detectedWidthPx / cardDimensions.width;

    return {
      type: 'credit-card',
      corners: scaledCorners,
      pixelsPerMm,
      confidence: best.score
    };
  }

  /**
   * Detect circular objects (coins)
   */
  private detectCoin(imageData: ImageData, scale: number): DetectedReference | null {
    const edges = this.sobelEdgeDetection(imageData);

    // Simple circle detection using Hough-like approach
    const circles = this.detectCircles(edges, imageData.width, imageData.height);

    if (circles.length === 0) {
      return null;
    }

    // Find the best circle (likely coin)
    // Prefer circles that are a reasonable size (not too small or too large)
    const minRadius = Math.min(imageData.width, imageData.height) * 0.03;
    const maxRadius = Math.min(imageData.width, imageData.height) * 0.2;

    const validCircles = circles.filter((c) => c.radius >= minRadius && c.radius <= maxRadius);

    if (validCircles.length === 0) {
      return null;
    }

    // Sort by confidence (accumulator value)
    validCircles.sort((a, b) => b.votes - a.votes);
    const best = validCircles[0];

    // Determine coin type based on radius ratio
    // If multiple coins detected, could compare ratios
    // For now, assume AU $1 coin (25mm diameter)
    const coinType: ReferenceObjectType = 'coin-au-dollar';
    const coinDiameter = REFERENCE_DIMENSIONS[coinType].width;

    // Create corner representation (square bounding the circle)
    const r = best.radius / scale;
    const cx = best.x / scale;
    const cy = best.y / scale;

    const corners: [
      { x: number; y: number },
      { x: number; y: number },
      { x: number; y: number },
      { x: number; y: number }
    ] = [
      { x: cx - r, y: cy - r },
      { x: cx + r, y: cy - r },
      { x: cx + r, y: cy + r },
      { x: cx - r, y: cy + r }
    ];

    const pixelsPerMm = (best.radius * 2) / scale / coinDiameter;

    return {
      type: coinType,
      corners,
      pixelsPerMm,
      confidence: Math.min(1, best.votes / 50)
    };
  }

  /**
   * Sobel edge detection
   */
  private sobelEdgeDetection(imageData: ImageData): EdgeData {
    const { data, width, height } = imageData;

    // Convert to grayscale
    const gray = new Uint8ClampedArray(width * height);
    for (let i = 0; i < width * height; i++) {
      const idx = i * 4;
      gray[i] = Math.round(data[idx] * 0.299 + data[idx + 1] * 0.587 + data[idx + 2] * 0.114);
    }

    // Sobel kernels
    const sobelX = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
    const sobelY = [-1, -2, -1, 0, 0, 0, 1, 2, 1];

    const edges = new Uint8ClampedArray(width * height);

    for (let y = 1; y < height - 1; y++) {
      for (let x = 1; x < width - 1; x++) {
        let gx = 0;
        let gy = 0;
        let k = 0;

        for (let ky = -1; ky <= 1; ky++) {
          for (let kx = -1; kx <= 1; kx++) {
            const pixel = gray[(y + ky) * width + (x + kx)];
            gx += pixel * sobelX[k];
            gy += pixel * sobelY[k];
            k++;
          }
        }

        const magnitude = Math.sqrt(gx * gx + gy * gy);
        edges[y * width + x] = magnitude > 50 ? 255 : 0;
      }
    }

    return { data: edges, width, height };
  }

  /**
   * Simple contour finding using connected component labeling
   */
  private findContours(edges: EdgeData): Contour[] {
    const { data, width, height } = edges;
    const visited = new Uint8Array(width * height);
    const contours: Contour[] = [];

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const idx = y * width + x;
        if (data[idx] === 255 && !visited[idx]) {
          const points = this.floodFill(data, visited, width, height, x, y);
          if (points.length >= 20) {
            // Minimum contour size
            const boundingBox = this.getBoundingBox(points);
            contours.push({
              points,
              boundingBox,
              area: boundingBox.width * boundingBox.height
            });
          }
        }
      }
    }

    return contours;
  }

  /**
   * Flood fill to find connected edge points
   */
  private floodFill(
    data: Uint8ClampedArray,
    visited: Uint8Array,
    width: number,
    height: number,
    startX: number,
    startY: number
  ): Array<{ x: number; y: number }> {
    const points: Array<{ x: number; y: number }> = [];
    const stack: Array<{ x: number; y: number }> = [{ x: startX, y: startY }];
    const maxPoints = 10000; // Limit to prevent huge contours

    while (stack.length > 0 && points.length < maxPoints) {
      const { x, y } = stack.pop()!;
      const idx = y * width + x;

      if (x < 0 || x >= width || y < 0 || y >= height) continue;
      if (visited[idx] || data[idx] !== 255) continue;

      visited[idx] = 1;
      points.push({ x, y });

      // 4-connected neighbors
      stack.push({ x: x + 1, y });
      stack.push({ x: x - 1, y });
      stack.push({ x, y: y + 1 });
      stack.push({ x, y: y - 1 });
    }

    return points;
  }

  /**
   * Get bounding box of points
   */
  private getBoundingBox(points: Array<{ x: number; y: number }>): {
    x: number;
    y: number;
    width: number;
    height: number;
  } {
    let minX = Infinity,
      maxX = -Infinity,
      minY = Infinity,
      maxY = -Infinity;

    for (const p of points) {
      minX = Math.min(minX, p.x);
      maxX = Math.max(maxX, p.x);
      minY = Math.min(minY, p.y);
      maxY = Math.max(maxY, p.y);
    }

    return {
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    };
  }

  /**
   * Find rectangular shapes from contours
   */
  private findRectangles(
    contours: Contour[],
    imageWidth: number,
    imageHeight: number
  ): RectangleCandidate[] {
    const rectangles: RectangleCandidate[] = [];

    for (const contour of contours) {
      // Skip very small or very large contours
      const relativeArea = contour.area / (imageWidth * imageHeight);
      if (relativeArea < 0.01 || relativeArea > 0.5) continue;

      const { boundingBox } = contour;
      const aspectRatio = boundingBox.width / boundingBox.height;

      // Check if roughly rectangular (aspect ratio between 0.5 and 3)
      if (aspectRatio < 0.5 || aspectRatio > 3) continue;

      // Calculate how "filled" the bounding box is by edge points
      const fillRatio = contour.points.length / (boundingBox.width * 2 + boundingBox.height * 2);
      const confidence = Math.min(1, fillRatio);

      const corners: RectangleCandidate['corners'] = [
        { x: boundingBox.x, y: boundingBox.y },
        { x: boundingBox.x + boundingBox.width, y: boundingBox.y },
        { x: boundingBox.x + boundingBox.width, y: boundingBox.y + boundingBox.height },
        { x: boundingBox.x, y: boundingBox.y + boundingBox.height }
      ];

      rectangles.push({
        corners,
        width: boundingBox.width,
        height: boundingBox.height,
        aspectRatio,
        area: contour.area,
        confidence
      });
    }

    return rectangles;
  }

  /**
   * Simple circle detection using voting
   */
  private detectCircles(
    edges: EdgeData,
    width: number,
    height: number
  ): Array<{ x: number; y: number; radius: number; votes: number }> {
    const { data } = edges;
    const circles: Map<string, { x: number; y: number; radius: number; votes: number }> = new Map();

    // Parameters
    const minRadius = Math.round(Math.min(width, height) * 0.02);
    const maxRadius = Math.round(Math.min(width, height) * 0.25);
    const radiusStep = 3;

    // For each edge point, vote for possible circle centers
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        if (data[y * width + x] !== 255) continue;

        // Vote for circles at different radii
        for (let r = minRadius; r <= maxRadius; r += radiusStep) {
          // Sample points around the edge point at distance r
          for (let angle = 0; angle < Math.PI * 2; angle += Math.PI / 8) {
            const cx = Math.round(x + r * Math.cos(angle));
            const cy = Math.round(y + r * Math.sin(angle));

            if (cx < 0 || cx >= width || cy < 0 || cy >= height) continue;

            // Quantise to reduce number of candidates
            const qx = Math.round(cx / 5) * 5;
            const qy = Math.round(cy / 5) * 5;
            const qr = Math.round(r / radiusStep) * radiusStep;
            const key = `${qx},${qy},${qr}`;

            const existing = circles.get(key);
            if (existing) {
              existing.votes++;
            } else {
              circles.set(key, { x: qx, y: qy, radius: qr, votes: 1 });
            }
          }
        }
      }
    }

    // Filter and sort by votes
    return Array.from(circles.values())
      .filter((c) => c.votes > 10)
      .sort((a, b) => b.votes - a.votes)
      .slice(0, 5);
  }

  /**
   * Load image from blob
   */
  private loadImage(blob: Blob): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = URL.createObjectURL(blob);
    });
  }

  /**
   * Manual reference input when auto-detection fails.
   * User provides corner points and reference type.
   */
  createManualReference(
    corners: [
      { x: number; y: number },
      { x: number; y: number },
      { x: number; y: number },
      { x: number; y: number }
    ],
    type: ReferenceObjectType
  ): DetectedReference {
    const dimensions = REFERENCE_DIMENSIONS[type];

    // Calculate width from corners (average of top and bottom edge)
    const topWidth = Math.sqrt(
      Math.pow(corners[1].x - corners[0].x, 2) + Math.pow(corners[1].y - corners[0].y, 2)
    );
    const bottomWidth = Math.sqrt(
      Math.pow(corners[2].x - corners[3].x, 2) + Math.pow(corners[2].y - corners[3].y, 2)
    );
    const avgWidth = (topWidth + bottomWidth) / 2;

    const pixelsPerMm = avgWidth / dimensions.width;

    return {
      type,
      corners,
      pixelsPerMm,
      confidence: 1.0 // Manual input = high confidence
    };
  }
}

export const referenceDetector = new ReferenceDetector();
