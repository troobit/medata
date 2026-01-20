/**
 * Workstream B: CGM Graph Image Capture Types
 * Owner: workstream-b/cgm-capture branch
 *
 * This file defines types for extracting BSL data from CGM app screenshots.
 * Implementations should be added to src/lib/services/cgm/
 */

import type { BSLUnit } from './events';

/**
 * Supported CGM device/app types
 */
export type CGMDeviceType = 'freestyle-libre' | 'dexcom' | 'medtronic' | 'generic';

/**
 * Detected axis ranges from graph image
 */
export interface AxisRanges {
  timeStart: Date;
  timeEnd: Date;
  bslMin: number;
  bslMax: number;
  unit: BSLUnit;
}

/**
 * Single extracted data point from graph
 */
export interface ExtractedDataPoint {
  timestamp: Date;
  value: number; // BSL reading
  confidence: number; // 0-1, how confident the extraction is
}

/**
 * Region of image containing the graph
 */
export interface GraphRegion {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Result from CGM graph extraction
 */
export interface CGMExtractionResult {
  deviceType: CGMDeviceType;
  axisRanges: AxisRanges;
  dataPoints: ExtractedDataPoint[];
  graphRegion: GraphRegion;
  extractionMethod: 'ml' | 'local-cv'; // ML-assisted or local computer vision
  processingTimeMs: number;
  warnings?: string[]; // e.g., "low confidence in some regions"
}

/**
 * Options for CGM graph extraction
 */
export interface CGMExtractionOptions {
  deviceType?: CGMDeviceType; // hint for parser selection
  manualAxisRanges?: Partial<AxisRanges>; // user-provided if auto-detection fails
  resampleIntervalMinutes?: number; // default 5
}

/**
 * Interface that CGM image processing services must implement
 * Implementations: CGMImageProcessor, LibreGraphParser, DexcomGraphParser
 */
export interface ICGMImageService {
  extractFromImage(image: Blob, options?: CGMExtractionOptions): Promise<CGMExtractionResult>;
  detectDeviceType(image: Blob): Promise<CGMDeviceType>;
  detectAxisRanges(image: Blob, region?: GraphRegion): Promise<AxisRanges>;
  isSupported(deviceType: CGMDeviceType): boolean;
}
