/**
 * Workstream B: Local Curve Extractor
 *
 * Extracts BSL time-series data from CGM graph images using local
 * computer vision algorithms (no cloud API required).
 *
 * Techniques used:
 * - Color-based line detection (filter by CGM line color)
 * - Edge detection for curve tracing
 * - Canvas-based pixel analysis
 */

import type {
  CGMDeviceType,
  CGMExtractionResult,
  CGMExtractionOptions,
  AxisRanges,
  ExtractedDataPoint,
  GraphRegion
} from '$lib/types/cgm';
import type { BSLUnit } from '$lib/types/events';

/**
 * Color profiles for different CGM devices
 */
interface ColorProfile {
  name: string;
  /** HSL ranges for the glucose line color */
  lineColor: {
    hueMin: number;
    hueMax: number;
    satMin: number;
    satMax: number;
    lightMin: number;
    lightMax: number;
  };
  /** Background colors to help identify graph region */
  backgroundColor?: {
    hueRange?: [number, number];
    isDark: boolean;
  };
}

const COLOR_PROFILES: Record<CGMDeviceType, ColorProfile> = {
  'freestyle-libre': {
    name: 'Freestyle Libre',
    lineColor: {
      // Yellow/orange line
      hueMin: 35,
      hueMax: 55,
      satMin: 70,
      satMax: 100,
      lightMin: 45,
      lightMax: 70
    },
    backgroundColor: {
      isDark: false // White background
    }
  },
  dexcom: {
    name: 'Dexcom',
    lineColor: {
      // Blue line
      hueMin: 190,
      hueMax: 230,
      satMin: 60,
      satMax: 100,
      lightMin: 40,
      lightMax: 70
    },
    backgroundColor: {
      isDark: true // Dark background
    }
  },
  medtronic: {
    name: 'Medtronic',
    lineColor: {
      // Blue gradient
      hueMin: 200,
      hueMax: 240,
      satMin: 50,
      satMax: 100,
      lightMin: 35,
      lightMax: 65
    },
    backgroundColor: {
      isDark: false
    }
  },
  generic: {
    name: 'Generic',
    lineColor: {
      // Accept wider range of colors
      hueMin: 0,
      hueMax: 360,
      satMin: 40,
      satMax: 100,
      lightMin: 30,
      lightMax: 70
    }
  }
};

/**
 * LocalCurveExtractor - Extracts BSL data from CGM images locally
 */
export class LocalCurveExtractor {
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
   * Load image into canvas for processing
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
   * Check if a pixel matches the line color profile
   */
  private matchesColorProfile(r: number, g: number, b: number, profile: ColorProfile): boolean {
    const [h, s, l] = this.rgbToHsl(r, g, b);

    const { lineColor } = profile;

    // Handle hue wraparound for red tones
    let hueMatch = false;
    if (lineColor.hueMin <= lineColor.hueMax) {
      hueMatch = h >= lineColor.hueMin && h <= lineColor.hueMax;
    } else {
      // Hue wraps around (e.g., red: 350-10)
      hueMatch = h >= lineColor.hueMin || h <= lineColor.hueMax;
    }

    return (
      hueMatch &&
      s >= lineColor.satMin &&
      s <= lineColor.satMax &&
      l >= lineColor.lightMin &&
      l <= lineColor.lightMax
    );
  }

  /**
   * Detect the graph region within the image
   */
  private detectGraphRegion(imageData: ImageData): GraphRegion {
    const { width, height, data } = imageData;

    // Find bounds of non-UI content (graph area)
    // Look for consistent patterns that indicate graph vs UI chrome

    let minX = width;
    let maxX = 0;
    let minY = height;
    let maxY = 0;

    // Simple approach: find where color variation is highest
    // This typically excludes solid color UI bars

    const rowVariance: number[] = [];
    const colVariance: number[] = [];

    // Calculate variance per row
    for (let y = 0; y < height; y++) {
      let sum = 0;
      let sumSq = 0;
      let count = 0;

      for (let x = 0; x < width; x++) {
        const idx = (y * width + x) * 4;
        const gray = (data[idx] + data[idx + 1] + data[idx + 2]) / 3;
        sum += gray;
        sumSq += gray * gray;
        count++;
      }

      const mean = sum / count;
      const variance = sumSq / count - mean * mean;
      rowVariance.push(variance);
    }

    // Calculate variance per column
    for (let x = 0; x < width; x++) {
      let sum = 0;
      let sumSq = 0;
      let count = 0;

      for (let y = 0; y < height; y++) {
        const idx = (y * width + x) * 4;
        const gray = (data[idx] + data[idx + 1] + data[idx + 2]) / 3;
        sum += gray;
        sumSq += gray * gray;
        count++;
      }

      const mean = sum / count;
      const variance = sumSq / count - mean * mean;
      colVariance.push(variance);
    }

    // Find high-variance regions (likely graph content)
    const varianceThreshold = 500;

    for (let y = 0; y < height; y++) {
      if (rowVariance[y] > varianceThreshold) {
        minY = Math.min(minY, y);
        maxY = Math.max(maxY, y);
      }
    }

    for (let x = 0; x < width; x++) {
      if (colVariance[x] > varianceThreshold) {
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x);
      }
    }

    // Add some padding
    const padding = 10;
    minX = Math.max(0, minX - padding);
    minY = Math.max(0, minY - padding);
    maxX = Math.min(width - 1, maxX + padding);
    maxY = Math.min(height - 1, maxY + padding);

    // Convert to percentages for consistency with ML output
    return {
      x: (minX / width) * 100,
      y: (minY / height) * 100,
      width: ((maxX - minX) / width) * 100,
      height: ((maxY - minY) / height) * 100
    };
  }

  /**
   * Detect device type based on image colors
   */
  detectDeviceType(imageData: ImageData): CGMDeviceType {
    const { width, height, data } = imageData;

    // Count pixels matching each profile
    const counts: Record<CGMDeviceType, number> = {
      'freestyle-libre': 0,
      dexcom: 0,
      medtronic: 0,
      generic: 0
    };

    // Sample pixels (not every pixel for performance)
    const sampleStep = 4;
    for (let y = 0; y < height; y += sampleStep) {
      for (let x = 0; x < width; x += sampleStep) {
        const idx = (y * width + x) * 4;
        const r = data[idx];
        const g = data[idx + 1];
        const b = data[idx + 2];

        for (const deviceType of ['freestyle-libre', 'dexcom', 'medtronic'] as CGMDeviceType[]) {
          if (this.matchesColorProfile(r, g, b, COLOR_PROFILES[deviceType])) {
            counts[deviceType]++;
          }
        }
      }
    }

    // Return device with highest count
    let maxCount = 0;
    let detected: CGMDeviceType = 'generic';

    for (const [device, count] of Object.entries(counts)) {
      if (count > maxCount && device !== 'generic') {
        maxCount = count;
        detected = device as CGMDeviceType;
      }
    }

    // Require minimum threshold to avoid false positives
    const totalSamples = (width / sampleStep) * (height / sampleStep);
    if (maxCount / totalSamples < 0.01) {
      return 'generic';
    }

    return detected;
  }

  /**
   * Extract line pixels from graph using color filtering
   */
  private extractLinePixels(
    imageData: ImageData,
    graphRegion: GraphRegion,
    profile: ColorProfile
  ): Array<{ x: number; y: number }> {
    const { width, height, data } = imageData;

    // Convert percentage region to pixels
    const regionX = Math.floor((graphRegion.x / 100) * width);
    const regionY = Math.floor((graphRegion.y / 100) * height);
    const regionW = Math.floor((graphRegion.width / 100) * width);
    const regionH = Math.floor((graphRegion.height / 100) * height);

    const linePixels: Array<{ x: number; y: number }> = [];

    // Scan for pixels matching the line color
    for (let y = regionY; y < regionY + regionH; y++) {
      for (let x = regionX; x < regionX + regionW; x++) {
        const idx = (y * width + x) * 4;
        const r = data[idx];
        const g = data[idx + 1];
        const b = data[idx + 2];

        if (this.matchesColorProfile(r, g, b, profile)) {
          linePixels.push({ x, y });
        }
      }
    }

    return linePixels;
  }

  /**
   * Trace the curve by finding the center of line pixels per column
   */
  private traceCurve(
    linePixels: Array<{ x: number; y: number }>,
    graphRegion: GraphRegion,
    imageWidth: number,
    _imageHeight: number
  ): Array<{ x: number; y: number }> {
    const regionX = Math.floor((graphRegion.x / 100) * imageWidth);
    const regionW = Math.floor((graphRegion.width / 100) * imageWidth);

    // Group pixels by x-coordinate (column)
    const columns = new Map<number, number[]>();

    for (const pixel of linePixels) {
      if (!columns.has(pixel.x)) {
        columns.set(pixel.x, []);
      }
      columns.get(pixel.x)!.push(pixel.y);
    }

    // For each column, find the center y value
    const curvePoints: Array<{ x: number; y: number }> = [];

    for (let x = regionX; x < regionX + regionW; x++) {
      const yValues = columns.get(x);
      if (yValues && yValues.length > 0) {
        // Use median to reduce noise
        yValues.sort((a, b) => a - b);
        const medianY = yValues[Math.floor(yValues.length / 2)];
        curvePoints.push({ x, y: medianY });
      }
    }

    // Sort by x-coordinate
    curvePoints.sort((a, b) => a.x - b.x);

    // Smooth the curve using moving average
    const smoothed: Array<{ x: number; y: number }> = [];
    const windowSize = 5;

    for (let i = 0; i < curvePoints.length; i++) {
      const start = Math.max(0, i - Math.floor(windowSize / 2));
      const end = Math.min(curvePoints.length, i + Math.ceil(windowSize / 2));
      let sumY = 0;
      let count = 0;

      for (let j = start; j < end; j++) {
        sumY += curvePoints[j].y;
        count++;
      }

      smoothed.push({
        x: curvePoints[i].x,
        y: sumY / count
      });
    }

    return smoothed;
  }

  /**
   * Convert curve points to BSL data points
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
      // Convert pixel position to time (x) and BSL (y)
      const xProgress = (point.x - regionX) / regionW;
      const yProgress = 1 - (point.y - regionY) / regionH; // Invert Y

      const timestamp = new Date(axisRanges.timeStart.getTime() + xProgress * timeRange);
      const value = axisRanges.bslMin + yProgress * bslRange;

      // Validate value is within expected range
      if (value >= axisRanges.bslMin && value <= axisRanges.bslMax) {
        dataPoints.push({
          timestamp,
          value: Math.round(value * 10) / 10,
          confidence: 0.8 // Local extraction has moderate confidence
        });
      }
    }

    return dataPoints;
  }

  /**
   * Resample data points to regular intervals
   */
  private resampleToIntervals(
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
      // Find closest point
      let closest: ExtractedDataPoint | null = null;
      let minDist = Infinity;

      for (const point of points) {
        const dist = Math.abs(point.timestamp.getTime() - t);
        if (dist < minDist) {
          minDist = dist;
          closest = point;
        }
      }

      if (closest && minDist < intervalMs * 2) {
        result.push({
          timestamp: new Date(t),
          value: closest.value,
          confidence: closest.confidence * (1 - minDist / (intervalMs * 2))
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

    // Load image into canvas
    const img = await this.loadImage(image);
    this.canvas.width = img.width;
    this.canvas.height = img.height;
    this.ctx.drawImage(img, 0, 0);

    // Get image data
    const imageData = this.ctx.getImageData(0, 0, img.width, img.height);

    // Detect device type if not provided
    const deviceType = options.deviceType || this.detectDeviceType(imageData);
    const profile = COLOR_PROFILES[deviceType];

    // Detect graph region
    const graphRegion = this.detectGraphRegion(imageData);

    // Extract line pixels using color filtering
    const linePixels = this.extractLinePixels(imageData, graphRegion, profile);

    if (linePixels.length < 50) {
      warnings.push('Low number of line pixels detected - extraction may be inaccurate');
    }

    // Trace the curve
    const curvePoints = this.traceCurve(linePixels, graphRegion, img.width, img.height);

    if (curvePoints.length < 20) {
      warnings.push('Could not trace continuous curve - data may be incomplete');
    }

    // Use provided axis ranges or defaults
    const axisRanges: AxisRanges = options.manualAxisRanges
      ? {
          timeStart: options.manualAxisRanges.timeStart || new Date(),
          timeEnd: options.manualAxisRanges.timeEnd || new Date(Date.now() + 8 * 60 * 60 * 1000),
          bslMin: options.manualAxisRanges.bslMin ?? 2,
          bslMax: options.manualAxisRanges.bslMax ?? 15,
          unit: options.manualAxisRanges.unit || 'mmol/L'
        }
      : this.estimateDefaultAxisRanges(deviceType);

    // Convert curve to data points
    const rawDataPoints = this.curveToDataPoints(
      curvePoints,
      graphRegion,
      axisRanges,
      img.width,
      img.height
    );

    // Resample to regular intervals
    const resampleInterval = options.resampleIntervalMinutes ?? 5;
    const dataPoints = this.resampleToIntervals(rawDataPoints, axisRanges, resampleInterval);

    // Cleanup
    URL.revokeObjectURL(img.src);

    const processingTimeMs = performance.now() - startTime;

    return {
      deviceType,
      axisRanges,
      dataPoints,
      graphRegion,
      extractionMethod: 'local-cv',
      processingTimeMs,
      warnings: warnings.length > 0 ? warnings : undefined
    };
  }

  /**
   * Estimate default axis ranges based on device type
   */
  private estimateDefaultAxisRanges(deviceType: CGMDeviceType): AxisRanges {
    const now = new Date();
    const today = new Date(now);
    today.setHours(0, 0, 0, 0);

    // Device-specific defaults
    const defaults: Record<CGMDeviceType, { unit: BSLUnit; min: number; max: number }> = {
      'freestyle-libre': { unit: 'mmol/L', min: 2.2, max: 13.3 },
      dexcom: { unit: 'mg/dL', min: 40, max: 400 },
      medtronic: { unit: 'mg/dL', min: 40, max: 400 },
      generic: { unit: 'mmol/L', min: 2, max: 15 }
    };

    const config = defaults[deviceType];

    return {
      // Default to 8-hour window ending now
      timeStart: new Date(now.getTime() - 8 * 60 * 60 * 1000),
      timeEnd: now,
      bslMin: config.min,
      bslMax: config.max,
      unit: config.unit
    };
  }

  /**
   * Check if local extraction is available (browser supports required APIs)
   */
  static isAvailable(): boolean {
    return typeof document !== 'undefined' && typeof HTMLCanvasElement !== 'undefined';
  }
}

/**
 * Factory function to create LocalCurveExtractor
 */
export function createLocalCurveExtractor(): LocalCurveExtractor {
  return new LocalCurveExtractor();
}
