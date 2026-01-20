/**
 * Workstream C: Local Food Volume Estimation Types
 * Owner: workstream-c/local-food branch
 *
 * This file defines types for browser-local food volume estimation.
 * No cloud API calls - all processing happens on device.
 * Implementations should be added to src/lib/services/local-estimation/
 */

import type { MacroData } from './events';

/**
 * Reference object types for scale detection
 */
export type ReferenceObjectType = 'credit-card' | 'coin-au-dollar' | 'coin-au-50c' | 'custom';

/**
 * Standard reference object dimensions (in mm)
 */
export const REFERENCE_DIMENSIONS: Record<ReferenceObjectType, { width: number; height: number }> =
  {
    'credit-card': { width: 85.6, height: 53.98 }, // ISO/IEC 7810 ID-1
    'coin-au-dollar': { width: 25, height: 25 }, // Australian $1 coin diameter
    'coin-au-50c': { width: 31.65, height: 31.65 }, // Australian 50c coin diameter
    custom: { width: 0, height: 0 } // user-provided
  };

/**
 * Detected reference object in image
 */
export interface DetectedReference {
  type: ReferenceObjectType;
  corners: [
    { x: number; y: number },
    { x: number; y: number },
    { x: number; y: number },
    { x: number; y: number }
  ];
  pixelsPerMm: number;
  confidence: number;
}

/**
 * Food region selected/detected in image
 */
export interface FoodRegion {
  id: string;
  boundary: Array<{ x: number; y: number }>; // polygon points
  estimatedAreaMm2: number;
  estimatedHeightMm?: number;
  estimatedVolumeMl?: number;
}

/**
 * Food type from density database
 */
export interface FoodDensityEntry {
  id: string;
  name: string;
  category: string;
  densityGPerMl: number; // grams per milliliter
  macrosPerGram: MacroData; // macros per gram of food
  usdaFoodCode?: string;
}

/**
 * Volume estimation result
 */
export interface VolumeEstimationResult {
  regions: FoodRegion[];
  totalVolumeMl: number;
  confidence: number;
  referenceUsed?: DetectedReference;
  warnings?: string[];
}

/**
 * Final macro estimation from local processing
 */
export interface LocalEstimationResult {
  volume: VolumeEstimationResult;
  foodType: FoodDensityEntry;
  estimatedWeightGrams: number;
  estimatedMacros: MacroData;
  confidence: number;
  processingTimeMs: number;
}

/**
 * Calibration data learned from user corrections
 */
export interface CalibrationEntry {
  foodTypeId: string;
  correctionFactor: number; // multiplier applied to estimates
  sampleCount: number;
  lastUpdated: Date;
}

/**
 * Interface for local volume estimation service
 * Implementations: ReferenceDetector, VolumeCalculator, FoodDensityLookup
 */
export interface IVolumeEstimationService {
  detectReference(image: Blob): Promise<DetectedReference | null>;
  estimateVolume(image: Blob, regions: FoodRegion[]): Promise<VolumeEstimationResult>;
  lookupFoodDensity(query: string): Promise<FoodDensityEntry[]>;
  calculateMacros(volume: VolumeEstimationResult, food: FoodDensityEntry): LocalEstimationResult;
  applyCalibration(result: LocalEstimationResult): LocalEstimationResult;
  saveCalibration(entry: CalibrationEntry): Promise<void>;
}
