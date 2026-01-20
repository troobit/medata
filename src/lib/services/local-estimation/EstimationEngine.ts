/**
 * Workstream C: Estimation Engine
 * Orchestrates the full local volume estimation pipeline.
 */

import type {
  FoodRegion,
  FoodDensityEntry,
  DetectedReference,
  VolumeEstimationResult,
  LocalEstimationResult,
  IVolumeEstimationService,
  CalibrationEntry
} from '$lib/types/local-estimation';
import { ReferenceDetector } from './ReferenceDetector';
import { VolumeCalculator, type ShapeTemplate } from './VolumeCalculator';
import { FoodDensityLookup } from './FoodDensityLookup';
import { CalibrationStore } from './CalibrationStore';

/**
 * Pipeline state for tracking estimation progress
 */
export interface EstimationState {
  step: 'capture' | 'reference' | 'region' | 'food-type' | 'result';
  imageBlob: Blob | null;
  reference: DetectedReference | null;
  regions: FoodRegion[];
  selectedFood: FoodDensityEntry | null;
  volumeResult: VolumeEstimationResult | null;
  finalResult: LocalEstimationResult | null;
}

/**
 * EstimationEngine orchestrates the full local volume estimation pipeline.
 * Implements IVolumeEstimationService interface.
 */
export class EstimationEngine implements IVolumeEstimationService {
  private referenceDetector: ReferenceDetector;
  private volumeCalculator: VolumeCalculator;
  private foodLookup: FoodDensityLookup;
  private calibrationStore: CalibrationStore;

  constructor() {
    this.referenceDetector = new ReferenceDetector();
    this.volumeCalculator = new VolumeCalculator();
    this.foodLookup = new FoodDensityLookup();
    this.calibrationStore = new CalibrationStore();
  }

  /**
   * Detect reference object in image
   */
  async detectReference(image: Blob): Promise<DetectedReference | null> {
    return this.referenceDetector.detect(image);
  }

  /**
   * Estimate volume from regions
   */
  async estimateVolume(
    image: Blob,
    regions: FoodRegion[],
    shape?: ShapeTemplate
  ): Promise<VolumeEstimationResult> {
    const reference = await this.detectReference(image);
    return this.volumeCalculator.estimateVolume(regions, reference, shape);
  }

  /**
   * Look up food density entries by query
   */
  async lookupFoodDensity(query: string): Promise<FoodDensityEntry[]> {
    return this.foodLookup.search(query);
  }

  /**
   * Calculate macros from volume and food type
   */
  calculateMacros(
    volume: VolumeEstimationResult,
    food: FoodDensityEntry
  ): LocalEstimationResult {
    const startTime = performance.now();

    const weightGrams = this.foodLookup.volumeToWeight(food, volume.totalVolumeMl);
    const macros = this.foodLookup.calculateMacros(food, weightGrams);

    const result: LocalEstimationResult = {
      volume,
      foodType: food,
      estimatedWeightGrams: Math.round(weightGrams),
      estimatedMacros: {
        calories: macros.calories,
        carbs: macros.carbs,
        protein: macros.protein,
        fat: macros.fat
      },
      confidence: volume.confidence,
      processingTimeMs: Math.round(performance.now() - startTime)
    };

    return result;
  }

  /**
   * Apply calibration adjustments to result
   */
  applyCalibration(result: LocalEstimationResult): LocalEstimationResult {
    const factor = this.calibrationStore.getCorrectionFactor(result.foodType.id);

    if (factor === 1.0) {
      return result;
    }

    return {
      ...result,
      estimatedWeightGrams: Math.round(result.estimatedWeightGrams * factor),
      estimatedMacros: {
        calories: Math.round(result.estimatedMacros.calories * factor),
        carbs: Math.round(result.estimatedMacros.carbs * factor * 10) / 10,
        protein: Math.round(result.estimatedMacros.protein * factor * 10) / 10,
        fat: Math.round(result.estimatedMacros.fat * factor * 10) / 10
      }
    };
  }

  /**
   * Save calibration from user correction
   */
  async saveCalibration(entry: CalibrationEntry): Promise<void> {
    this.calibrationStore.recordCorrection({
      foodTypeId: entry.foodTypeId,
      estimatedValue: 1,
      correctedValue: entry.correctionFactor,
      field: 'carbs'
    });
  }

  /**
   * Record a user correction for learning
   */
  recordUserCorrection(
    result: LocalEstimationResult,
    correctedCarbs: number
  ): void {
    if (result.estimatedMacros.carbs === 0) return;

    this.calibrationStore.recordCorrection({
      foodTypeId: result.foodType.id,
      estimatedValue: result.estimatedMacros.carbs,
      correctedValue: correctedCarbs,
      field: 'carbs'
    });
  }

  /**
   * Full estimation pipeline from image + regions + food selection
   */
  async estimate(
    imageBlob: Blob,
    regions: FoodRegion[],
    food: FoodDensityEntry,
    shape?: ShapeTemplate
  ): Promise<LocalEstimationResult> {
    // Step 1: Detect reference (or use provided)
    const reference = await this.detectReference(imageBlob);

    // Step 2: Calculate volume
    const suggestedShape = shape ?? this.volumeCalculator.suggestShape(food.name);
    const volume = this.volumeCalculator.estimateVolume(regions, reference, suggestedShape);

    // Step 3: Calculate macros
    let result = this.calculateMacros(volume, food);

    // Step 4: Apply calibration
    result = this.applyCalibration(result);

    return result;
  }

  /**
   * Quick estimate with simplified inputs
   */
  async quickEstimate(
    imageBlob: Blob,
    foodId: string,
    regionPoints: Array<{ x: number; y: number }>
  ): Promise<LocalEstimationResult | null> {
    const food = this.foodLookup.getById(foodId);
    if (!food) return null;

    const region: FoodRegion = {
      id: crypto.randomUUID(),
      boundary: regionPoints,
      estimatedAreaMm2: 0
    };

    return this.estimate(imageBlob, [region], food);
  }

  /**
   * Get the food lookup service for UI components
   */
  getFoodLookup(): FoodDensityLookup {
    return this.foodLookup;
  }

  /**
   * Get the volume calculator for UI components
   */
  getVolumeCalculator(): VolumeCalculator {
    return this.volumeCalculator;
  }

  /**
   * Get calibration statistics
   */
  getCalibrationStats(): {
    totalFoods: number;
    totalCorrections: number;
    averageDeviation: number;
  } {
    return this.calibrationStore.getStats();
  }

  /**
   * Export calibration data
   */
  exportCalibration(): string {
    return this.calibrationStore.export();
  }

  /**
   * Import calibration data
   */
  importCalibration(json: string): void {
    this.calibrationStore.import(json);
  }

  /**
   * Create initial state for the estimation flow
   */
  createInitialState(): EstimationState {
    return {
      step: 'capture',
      imageBlob: null,
      reference: null,
      regions: [],
      selectedFood: null,
      volumeResult: null,
      finalResult: null
    };
  }
}

// Singleton instance
export const estimationEngine = new EstimationEngine();
