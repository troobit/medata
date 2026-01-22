/**
 * Workstream B: Freestyle Libre Graph Parser
 *
 * Specialized parser for Freestyle Libre CGM screenshots.
 * Optimized for the Libre app's specific graph format:
 * - Yellow/orange glucose line on white/light background
 * - Target range bands (typically green shaded area)
 * - Time scale options: 8h, 12h, 24h
 * - Y-axis: typically 2.2-13.3 mmol/L or 40-240 mg/dL
 */

import type {
  CGMExtractionResult,
  CGMExtractionOptions,
  AxisRanges,
  ExtractedDataPoint,
  GraphRegion
} from '$lib/types/cgm';
import type { BSLUnit } from '$lib/types/events';

/**
 * Libre-specific color definitions
 */
const LIBRE_COLORS = {
  // Yellow/orange glucose line
  glucoseLine: {
    hueMin: 35,
    hueMax: 55,
    satMin: 80,
    satMax: 100,
    lightMin: 50,
    lightMax: 65
  },
  // Green target range band
  targetRange: {
    hueMin: 80,
    hueMax: 140,
    satMin: 30,
    satMax: 80,
    lightMin: 40,
    lightMax: 80
  },
  // Red low/high alerts
  alertColor: {
    hueMin: 350,
    hueMax: 10, // Wraps around
    satMin: 60,
    satMax: 100,
    lightMin: 40,
    lightMax: 60
  }
};

/**
 * Common Libre graph configurations
 * Note: Currently used for type reference in estimateTimeRange
 */
type LibrePresetKey = '8h' | '12h' | '24h';
const _LIBRE_PRESETS: Record<
  LibrePresetKey,
  { durationHours: number; expectedDataPoints: number }
> = {
  '8h': {
    durationHours: 8,
    expectedDataPoints: 96 // 5-min intervals
  },
  '12h': {
    durationHours: 12,
    expectedDataPoints: 144
  },
  '24h': {
    durationHours: 24,
    expectedDataPoints: 288
  }
};

/**
 * LibreGraphParser - Specialized parser for Freestyle Libre screenshots
 */
export class LibreGraphParser {
  private canvas: HTMLCanvasElement;
  private ctx: CanvasRenderingContext2D;

  constructor() {
    this.canvas = document.createElement('canvas');
    const ctx = this.canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) {
      throw new Error('Could not get 2D canvas context');
    }
    this.ctx = ctx;
  }

  /**
   * Load image into canvas
   */
  private async loadImage(blob: Blob): Promise<HTMLImageElement> {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error('Failed to load image'));
      img.src = URL.createObjectURL(blob);
    });
  }

  /**
   * Convert RGB to HSL
   */
  private rgbToHsl(r: number, g: number, b: number): [number, number, number] {
    r /= 255;
    g /= 255;
    b /= 255;

    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    let h = 0;
    let s = 0;
    const l = (max + min) / 2;

    if (max !== min) {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);

      switch (max) {
        case r:
          h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
          break;
        case g:
          h = ((b - r) / d + 2) / 6;
          break;
        case b:
          h = ((r - g) / d + 4) / 6;
          break;
      }
    }

    return [h * 360, s * 100, l * 100];
  }

  /**
   * Check if pixel matches Libre glucose line color
   */
  private isGlucoseLinePixel(r: number, g: number, b: number): boolean {
    const [h, s, l] = this.rgbToHsl(r, g, b);
    const { glucoseLine } = LIBRE_COLORS;

    return (
      h >= glucoseLine.hueMin &&
      h <= glucoseLine.hueMax &&
      s >= glucoseLine.satMin &&
      s <= glucoseLine.satMax &&
      l >= glucoseLine.lightMin &&
      l <= glucoseLine.lightMax
    );
  }

  /**
   * Check if pixel is in target range band (green)
   */
  private isTargetRangePixel(r: number, g: number, b: number): boolean {
    const [h, s, l] = this.rgbToHsl(r, g, b);
    const { targetRange } = LIBRE_COLORS;

    return (
      h >= targetRange.hueMin &&
      h <= targetRange.hueMax &&
      s >= targetRange.satMin &&
      s <= targetRange.satMax &&
      l >= targetRange.lightMin &&
      l <= targetRange.lightMax
    );
  }

  /**
   * Detect graph region by finding the target range band
   */
  private detectGraphRegion(imageData: ImageData): GraphRegion {
    const { width, height, data } = imageData;

    // Find bounds of the green target range band
    let minX = width;
    let maxX = 0;
    let minY = height;
    let maxY = 0;

    // Also track yellow line bounds
    let lineMinX = width;
    let lineMaxX = 0;
    let lineMinY = height;
    let lineMaxY = 0;

    const sampleStep = 2;

    for (let y = 0; y < height; y += sampleStep) {
      for (let x = 0; x < width; x += sampleStep) {
        const idx = (y * width + x) * 4;
        const r = data[idx];
        const g = data[idx + 1];
        const b = data[idx + 2];

        if (this.isTargetRangePixel(r, g, b)) {
          minX = Math.min(minX, x);
          maxX = Math.max(maxX, x);
          minY = Math.min(minY, y);
          maxY = Math.max(maxY, y);
        }

        if (this.isGlucoseLinePixel(r, g, b)) {
          lineMinX = Math.min(lineMinX, x);
          lineMaxX = Math.max(lineMaxX, x);
          lineMinY = Math.min(lineMinY, y);
          lineMaxY = Math.max(lineMaxY, y);
        }
      }
    }

    // Use whichever bounds are wider (prefer target range if available)
    let regionX = minX;
    let regionY = minY;
    let regionW = maxX - minX;
    let regionH = maxY - minY;

    // Fall back to line bounds if target range not found
    if (regionW < 50 || regionH < 50) {
      regionX = lineMinX;
      regionY = lineMinY;
      regionW = lineMaxX - lineMinX;
      regionH = lineMaxY - lineMinY;
    }

    // Add padding
    const paddingX = Math.max(10, regionW * 0.02);
    const paddingY = Math.max(10, regionH * 0.05);

    regionX = Math.max(0, regionX - paddingX);
    regionY = Math.max(0, regionY - paddingY);
    regionW = Math.min(width - regionX, regionW + 2 * paddingX);
    regionH = Math.min(height - regionY, regionH + 2 * paddingY);

    return {
      x: (regionX / width) * 100,
      y: (regionY / height) * 100,
      width: (regionW / width) * 100,
      height: (regionH / height) * 100
    };
  }

  /**
   * Extract glucose line pixels
   */
  private extractLinePixels(
    imageData: ImageData,
    graphRegion: GraphRegion
  ): Array<{ x: number; y: number }> {
    const { width, height, data } = imageData;

    const regionX = Math.floor((graphRegion.x / 100) * width);
    const regionY = Math.floor((graphRegion.y / 100) * height);
    const regionW = Math.floor((graphRegion.width / 100) * width);
    const regionH = Math.floor((graphRegion.height / 100) * height);

    const pixels: Array<{ x: number; y: number }> = [];

    for (let y = regionY; y < regionY + regionH; y++) {
      for (let x = regionX; x < regionX + regionW; x++) {
        const idx = (y * width + x) * 4;
        if (this.isGlucoseLinePixel(data[idx], data[idx + 1], data[idx + 2])) {
          pixels.push({ x, y });
        }
      }
    }

    return pixels;
  }

  /**
   * Trace curve using column-wise median
   */
  private traceCurve(
    linePixels: Array<{ x: number; y: number }>,
    graphRegion: GraphRegion,
    width: number
  ): Array<{ x: number; y: number }> {
    const regionX = Math.floor((graphRegion.x / 100) * width);
    const regionW = Math.floor((graphRegion.width / 100) * width);

    // Group by column
    const columns = new Map<number, number[]>();
    for (const pixel of linePixels) {
      if (!columns.has(pixel.x)) {
        columns.set(pixel.x, []);
      }
      columns.get(pixel.x)!.push(pixel.y);
    }

    // Extract median per column
    const points: Array<{ x: number; y: number }> = [];

    for (let x = regionX; x < regionX + regionW; x++) {
      const yValues = columns.get(x);
      if (yValues && yValues.length > 0) {
        yValues.sort((a, b) => a - b);
        const median = yValues[Math.floor(yValues.length / 2)];
        points.push({ x, y: median });
      }
    }

    // Apply smoothing
    return this.smoothCurve(points, 5);
  }

  /**
   * Smooth curve using moving average
   */
  private smoothCurve(
    points: Array<{ x: number; y: number }>,
    windowSize: number
  ): Array<{ x: number; y: number }> {
    const smoothed: Array<{ x: number; y: number }> = [];
    const halfWindow = Math.floor(windowSize / 2);

    for (let i = 0; i < points.length; i++) {
      const start = Math.max(0, i - halfWindow);
      const end = Math.min(points.length, i + halfWindow + 1);
      let sumY = 0;

      for (let j = start; j < end; j++) {
        sumY += points[j].y;
      }

      smoothed.push({
        x: points[i].x,
        y: sumY / (end - start)
      });
    }

    return smoothed;
  }

  /**
   * Estimate time range from graph width
   */
  private estimateTimeRange(
    curvePoints: Array<{ x: number; y: number }>,
    _graphRegion: GraphRegion,
    _width: number
  ): { durationHours: number; preset: LibrePresetKey } {
    // Count data points to estimate time range
    // Note: Point density analysis could be used in future for more accurate detection

    // Libre shows approximately 12 pixels per 5 minutes for 8h view
    // This varies by device resolution

    // Default to 8h if uncertain
    if (curvePoints.length < 100) {
      return { durationHours: 8, preset: '8h' };
    } else if (curvePoints.length < 200) {
      return { durationHours: 12, preset: '12h' };
    } else {
      return { durationHours: 24, preset: '24h' };
    }
  }

  /**
   * Convert curve to BSL data points
   */
  private curveToDataPoints(
    curvePoints: Array<{ x: number; y: number }>,
    graphRegion: GraphRegion,
    axisRanges: AxisRanges,
    imageWidth: number,
    imageHeight: number
  ): ExtractedDataPoint[] {
    const regionX = Math.floor((graphRegion.x / 100) * imageWidth);
    const regionY = Math.floor((graphRegion.y / 100) * imageHeight);
    const regionW = Math.floor((graphRegion.width / 100) * imageWidth);
    const regionH = Math.floor((graphRegion.height / 100) * imageHeight);

    const timeRange = axisRanges.timeEnd.getTime() - axisRanges.timeStart.getTime();
    const bslRange = axisRanges.bslMax - axisRanges.bslMin;

    const dataPoints: ExtractedDataPoint[] = [];

    for (const point of curvePoints) {
      const xProgress = (point.x - regionX) / regionW;
      const yProgress = 1 - (point.y - regionY) / regionH;

      const timestamp = new Date(axisRanges.timeStart.getTime() + xProgress * timeRange);
      const value = axisRanges.bslMin + yProgress * bslRange;

      if (value >= axisRanges.bslMin && value <= axisRanges.bslMax) {
        dataPoints.push({
          timestamp,
          value: Math.round(value * 10) / 10,
          confidence: 0.85 // Libre-specific parser has higher confidence
        });
      }
    }

    return dataPoints;
  }

  /**
   * Resample to 5-minute intervals
   */
  private resample(
    points: ExtractedDataPoint[],
    axisRanges: AxisRanges,
    intervalMinutes: number
  ): ExtractedDataPoint[] {
    if (points.length < 2) return points;

    const result: ExtractedDataPoint[] = [];
    const startTime = axisRanges.timeStart.getTime();
    const endTime = axisRanges.timeEnd.getTime();
    const intervalMs = intervalMinutes * 60 * 1000;

    for (let t = startTime; t <= endTime; t += intervalMs) {
      // Linear interpolation between nearest points
      let before: ExtractedDataPoint | null = null;
      let after: ExtractedDataPoint | null = null;

      for (const point of points) {
        const pt = point.timestamp.getTime();
        if (pt <= t && (!before || pt > before.timestamp.getTime())) {
          before = point;
        }
        if (pt >= t && (!after || pt < after.timestamp.getTime())) {
          after = point;
        }
      }

      if (before && after) {
        const beforeT = before.timestamp.getTime();
        const afterT = after.timestamp.getTime();

        let value: number;
        let confidence: number;

        if (beforeT === afterT) {
          value = before.value;
          confidence = before.confidence;
        } else {
          const ratio = (t - beforeT) / (afterT - beforeT);
          value = before.value + ratio * (after.value - before.value);
          confidence = Math.min(before.confidence, after.confidence);
        }

        result.push({
          timestamp: new Date(t),
          value: Math.round(value * 10) / 10,
          confidence
        });
      }
    }

    return result;
  }

  /**
   * Main extraction method
   */
  async extractFromImage(
    image: Blob,
    options: CGMExtractionOptions = {}
  ): Promise<CGMExtractionResult> {
    const startTime = performance.now();
    const warnings: string[] = [];

    // Load image
    const img = await this.loadImage(image);
    this.canvas.width = img.width;
    this.canvas.height = img.height;
    this.ctx.drawImage(img, 0, 0);

    const imageData = this.ctx.getImageData(0, 0, img.width, img.height);

    // Detect graph region
    const graphRegion = this.detectGraphRegion(imageData);

    // Extract line pixels
    const linePixels = this.extractLinePixels(imageData, graphRegion);

    if (linePixels.length < 30) {
      warnings.push('Low glucose line detection - image may not be a Libre screenshot');
    }

    // Trace curve
    const curvePoints = this.traceCurve(linePixels, graphRegion, img.width);

    // Estimate time range
    const timeEstimate = this.estimateTimeRange(curvePoints, graphRegion, img.width);

    // Build axis ranges
    const now = new Date();
    const axisRanges: AxisRanges = options.manualAxisRanges
      ? {
          timeStart:
            options.manualAxisRanges.timeStart ||
            new Date(now.getTime() - timeEstimate.durationHours * 60 * 60 * 1000),
          timeEnd: options.manualAxisRanges.timeEnd || now,
          bslMin: options.manualAxisRanges.bslMin ?? 2.2,
          bslMax: options.manualAxisRanges.bslMax ?? 13.3,
          unit: options.manualAxisRanges.unit || 'mmol/L'
        }
      : {
          timeStart: new Date(now.getTime() - timeEstimate.durationHours * 60 * 60 * 1000),
          timeEnd: now,
          bslMin: 2.2,
          bslMax: 13.3,
          unit: 'mmol/L' as BSLUnit
        };

    // Convert to data points
    const rawPoints = this.curveToDataPoints(
      curvePoints,
      graphRegion,
      axisRanges,
      img.width,
      img.height
    );

    // Resample
    const resampleInterval = options.resampleIntervalMinutes ?? 5;
    const dataPoints = this.resample(rawPoints, axisRanges, resampleInterval);

    // Cleanup
    URL.revokeObjectURL(img.src);

    return {
      deviceType: 'freestyle-libre',
      axisRanges,
      dataPoints,
      graphRegion,
      extractionMethod: 'local-cv',
      processingTimeMs: performance.now() - startTime,
      warnings: warnings.length > 0 ? warnings : undefined
    };
  }
}

/**
 * Factory function
 */
export function createLibreGraphParser(): LibreGraphParser {
  return new LibreGraphParser();
}
