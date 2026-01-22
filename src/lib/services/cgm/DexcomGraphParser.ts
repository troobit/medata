/**
 * Workstream B: Dexcom Graph Parser
 *
 * Specialized parser for Dexcom G6/G7 CGM screenshots.
 * Optimized for the Dexcom app's specific graph format:
 * - Blue/teal glucose line on dark background
 * - Gray/white target range bands
 * - Time scale options: 3h, 6h, 12h, 24h
 * - Y-axis: typically 40-400 mg/dL (US) or 2.2-22.2 mmol/L (international)
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
 * Dexcom-specific color definitions
 */
const DEXCOM_COLORS = {
  // Blue/teal glucose line
  glucoseLine: {
    hueMin: 180,
    hueMax: 220,
    satMin: 50,
    satMax: 100,
    lightMin: 45,
    lightMax: 70
  },
  // Alternative cyan line (some Dexcom versions)
  glucoseLineCyan: {
    hueMin: 170,
    hueMax: 195,
    satMin: 60,
    satMax: 100,
    lightMin: 50,
    lightMax: 75
  },
  // Green in-range color
  inRangeGreen: {
    hueMin: 100,
    hueMax: 150,
    satMin: 40,
    satMax: 90,
    lightMin: 35,
    lightMax: 60
  },
  // Yellow/orange warning
  warningColor: {
    hueMin: 30,
    hueMax: 50,
    satMin: 70,
    satMax: 100,
    lightMin: 45,
    lightMax: 65
  },
  // Red urgent
  urgentColor: {
    hueMin: 350,
    hueMax: 15,
    satMin: 70,
    satMax: 100,
    lightMin: 40,
    lightMax: 60
  }
};

/**
 * Common Dexcom graph configurations
 * Note: Currently unused but kept for future preset detection
 */
const _DEXCOM_PRESETS = {
  '3h': { durationHours: 3, expectedDataPoints: 36 },
  '6h': { durationHours: 6, expectedDataPoints: 72 },
  '12h': { durationHours: 12, expectedDataPoints: 144 },
  '24h': { durationHours: 24, expectedDataPoints: 288 }
};

/**
 * DexcomGraphParser - Specialized parser for Dexcom screenshots
 */
export class DexcomGraphParser {
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
   * Check if pixel matches color range (handling hue wraparound)
   */
  private matchesColorRange(
    r: number,
    g: number,
    b: number,
    range: {
      hueMin: number;
      hueMax: number;
      satMin: number;
      satMax: number;
      lightMin: number;
      lightMax: number;
    }
  ): boolean {
    const [h, s, l] = this.rgbToHsl(r, g, b);

    let hueMatch = false;
    if (range.hueMin <= range.hueMax) {
      hueMatch = h >= range.hueMin && h <= range.hueMax;
    } else {
      hueMatch = h >= range.hueMin || h <= range.hueMax;
    }

    return (
      hueMatch &&
      s >= range.satMin &&
      s <= range.satMax &&
      l >= range.lightMin &&
      l <= range.lightMax
    );
  }

  /**
   * Check if pixel is part of glucose line
   */
  private isGlucoseLinePixel(r: number, g: number, b: number): boolean {
    return (
      this.matchesColorRange(r, g, b, DEXCOM_COLORS.glucoseLine) ||
      this.matchesColorRange(r, g, b, DEXCOM_COLORS.glucoseLineCyan)
    );
  }

  /**
   * Check if pixel is in-range green
   */
  private isInRangePixel(r: number, g: number, b: number): boolean {
    return this.matchesColorRange(r, g, b, DEXCOM_COLORS.inRangeGreen);
  }

  /**
   * Detect if image has dark background (typical Dexcom)
   */
  private hasDarkBackground(imageData: ImageData): boolean {
    const { width, height, data } = imageData;
    let darkPixels = 0;
    let totalSampled = 0;
    const sampleStep = 10;

    for (let y = 0; y < height; y += sampleStep) {
      for (let x = 0; x < width; x += sampleStep) {
        const idx = (y * width + x) * 4;
        const brightness = (data[idx] + data[idx + 1] + data[idx + 2]) / 3;
        if (brightness < 80) {
          darkPixels++;
        }
        totalSampled++;
      }
    }

    return darkPixels / totalSampled > 0.4;
  }

  /**
   * Detect graph region
   */
  private detectGraphRegion(imageData: ImageData): GraphRegion {
    const { width, height, data } = imageData;

    let minX = width;
    let maxX = 0;
    let minY = height;
    let maxY = 0;

    const sampleStep = 2;

    // Find bounds of colored elements (glucose line, in-range areas)
    for (let y = 0; y < height; y += sampleStep) {
      for (let x = 0; x < width; x += sampleStep) {
        const idx = (y * width + x) * 4;
        const r = data[idx];
        const g = data[idx + 1];
        const b = data[idx + 2];

        if (this.isGlucoseLinePixel(r, g, b) || this.isInRangePixel(r, g, b)) {
          minX = Math.min(minX, x);
          maxX = Math.max(maxX, x);
          minY = Math.min(minY, y);
          maxY = Math.max(maxY, y);
        }
      }
    }

    // Add padding
    const paddingX = Math.max(10, (maxX - minX) * 0.02);
    const paddingY = Math.max(10, (maxY - minY) * 0.05);

    minX = Math.max(0, minX - paddingX);
    minY = Math.max(0, minY - paddingY);
    maxX = Math.min(width - 1, maxX + paddingX);
    maxY = Math.min(height - 1, maxY + paddingY);

    return {
      x: (minX / width) * 100,
      y: (minY / height) * 100,
      width: ((maxX - minX) / width) * 100,
      height: ((maxY - minY) / height) * 100
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
   * Trace curve with noise reduction
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

    // Apply stronger smoothing for Dexcom (often has more noise)
    return this.smoothCurve(points, 7);
  }

  /**
   * Smooth curve using weighted moving average
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
      let totalWeight = 0;

      for (let j = start; j < end; j++) {
        // Gaussian-like weights (closer points weighted more)
        const distance = Math.abs(j - i);
        const weight = 1 / (1 + distance * 0.5);
        sumY += points[j].y * weight;
        totalWeight += weight;
      }

      smoothed.push({
        x: points[i].x,
        y: sumY / totalWeight
      });
    }

    return smoothed;
  }

  /**
   * Estimate time range from point density
   */
  private estimateTimeRange(curvePoints: Array<{ x: number; y: number }>): {
    durationHours: number;
  } {
    // Dexcom typically has consistent point density
    // Estimate based on curve length
    if (curvePoints.length < 50) {
      return { durationHours: 3 };
    } else if (curvePoints.length < 100) {
      return { durationHours: 6 };
    } else if (curvePoints.length < 200) {
      return { durationHours: 12 };
    } else {
      return { durationHours: 24 };
    }
  }

  /**
   * Detect if using mg/dL or mmol/L based on typical value ranges
   */
  private detectUnit(
    _curvePoints: Array<{ x: number; y: number }>,
    _graphRegion: GraphRegion,
    _imageHeight: number
  ): BSLUnit {
    // Analyze y-position distribution
    // mg/dL typically uses larger range (40-400)
    // mmol/L typically uses smaller range (2.2-22.2)

    // For now, assume mg/dL for Dexcom (most common in US market)
    // Users can override in axis adjustment
    return 'mg/dL';
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
          value: Math.round(value),
          confidence: 0.82
        });
      }
    }

    return dataPoints;
  }

  /**
   * Resample to regular intervals
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
          value: Math.round(value),
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

    // Verify dark background (Dexcom characteristic)
    if (!this.hasDarkBackground(imageData)) {
      warnings.push('Image does not have typical Dexcom dark background');
    }

    // Detect graph region
    const graphRegion = this.detectGraphRegion(imageData);

    // Extract line pixels
    const linePixels = this.extractLinePixels(imageData, graphRegion);

    if (linePixels.length < 30) {
      warnings.push('Low glucose line detection - image may not be a Dexcom screenshot');
    }

    // Trace curve
    const curvePoints = this.traceCurve(linePixels, graphRegion, img.width);

    // Estimate time range and unit
    const timeEstimate = this.estimateTimeRange(curvePoints);
    const detectedUnit = this.detectUnit(curvePoints, graphRegion, img.height);

    // Build axis ranges
    const now = new Date();
    const axisRanges: AxisRanges = options.manualAxisRanges
      ? {
          timeStart:
            options.manualAxisRanges.timeStart ||
            new Date(now.getTime() - timeEstimate.durationHours * 60 * 60 * 1000),
          timeEnd: options.manualAxisRanges.timeEnd || now,
          bslMin: options.manualAxisRanges.bslMin ?? (detectedUnit === 'mg/dL' ? 40 : 2.2),
          bslMax: options.manualAxisRanges.bslMax ?? (detectedUnit === 'mg/dL' ? 400 : 22.2),
          unit: options.manualAxisRanges.unit || detectedUnit
        }
      : {
          timeStart: new Date(now.getTime() - timeEstimate.durationHours * 60 * 60 * 1000),
          timeEnd: now,
          bslMin: detectedUnit === 'mg/dL' ? 40 : 2.2,
          bslMax: detectedUnit === 'mg/dL' ? 400 : 22.2,
          unit: detectedUnit
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
      deviceType: 'dexcom',
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
export function createDexcomGraphParser(): DexcomGraphParser {
  return new DexcomGraphParser();
}
