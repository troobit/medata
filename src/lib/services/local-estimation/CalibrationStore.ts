/**
 * Workstream C: Calibration Store
 * Stores and manages learned calibration factors from user corrections.
 * Uses localStorage for persistence.
 */

import type { CalibrationEntry } from '$lib/types/local-estimation';

const STORAGE_KEY = 'medata_calibration';

/**
 * Correction input from user
 */
export interface CorrectionInput {
  foodTypeId: string;
  estimatedValue: number;
  correctedValue: number;
  field: 'carbs' | 'calories' | 'protein' | 'fat' | 'volume';
}

/**
 * CalibrationStore manages learned correction factors from user feedback
 */
export class CalibrationStore {
  private calibrations: Map<string, CalibrationEntry>;
  private loaded: boolean = false;

  constructor() {
    this.calibrations = new Map();
  }

  /**
   * Load calibrations from localStorage
   */
  private load(): void {
    if (this.loaded) return;

    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const data = JSON.parse(stored) as CalibrationEntry[];
        for (const entry of data) {
          // Convert date string back to Date
          entry.lastUpdated = new Date(entry.lastUpdated);
          this.calibrations.set(entry.foodTypeId, entry);
        }
      }
    } catch (e) {
      console.warn('Failed to load calibration data:', e);
    }

    this.loaded = true;
  }

  /**
   * Save calibrations to localStorage
   */
  private save(): void {
    try {
      const data = Array.from(this.calibrations.values());
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    } catch (e) {
      console.warn('Failed to save calibration data:', e);
    }
  }

  /**
   * Get calibration entry for a food type
   */
  get(foodTypeId: string): CalibrationEntry | undefined {
    this.load();
    return this.calibrations.get(foodTypeId);
  }

  /**
   * Get correction factor for a food type (1.0 = no correction)
   */
  getCorrectionFactor(foodTypeId: string): number {
    const entry = this.get(foodTypeId);
    return entry?.correctionFactor ?? 1.0;
  }

  /**
   * Record a user correction and update calibration
   */
  recordCorrection(correction: CorrectionInput): void {
    this.load();

    const existing = this.calibrations.get(correction.foodTypeId);

    if (correction.estimatedValue === 0) return; // Avoid division by zero

    const newCorrectionFactor = correction.correctedValue / correction.estimatedValue;

    if (existing) {
      // Running average of correction factors
      // Weight newer corrections slightly more (exponential moving average)
      const alpha = 0.3; // Weight for new value
      const updatedFactor =
        alpha * newCorrectionFactor + (1 - alpha) * existing.correctionFactor;

      existing.correctionFactor = Math.round(updatedFactor * 1000) / 1000;
      existing.sampleCount += 1;
      existing.lastUpdated = new Date();
    } else {
      // First correction for this food type
      this.calibrations.set(correction.foodTypeId, {
        foodTypeId: correction.foodTypeId,
        correctionFactor: Math.round(newCorrectionFactor * 1000) / 1000,
        sampleCount: 1,
        lastUpdated: new Date()
      });
    }

    this.save();
  }

  /**
   * Apply calibration to a value
   */
  applyCalibration(foodTypeId: string, value: number): number {
    const factor = this.getCorrectionFactor(foodTypeId);
    return Math.round(value * factor * 10) / 10;
  }

  /**
   * Get all calibration entries
   */
  getAll(): CalibrationEntry[] {
    this.load();
    return Array.from(this.calibrations.values());
  }

  /**
   * Clear all calibrations
   */
  clear(): void {
    this.calibrations.clear();
    localStorage.removeItem(STORAGE_KEY);
  }

  /**
   * Export calibrations as JSON
   */
  export(): string {
    this.load();
    return JSON.stringify(Array.from(this.calibrations.values()), null, 2);
  }

  /**
   * Import calibrations from JSON
   */
  import(json: string): void {
    try {
      const data = JSON.parse(json) as CalibrationEntry[];
      for (const entry of data) {
        entry.lastUpdated = new Date(entry.lastUpdated);
        this.calibrations.set(entry.foodTypeId, entry);
      }
      this.save();
    } catch (e) {
      throw new Error('Invalid calibration data format');
    }
  }

  /**
   * Get statistics about calibrations
   */
  getStats(): {
    totalFoods: number;
    totalCorrections: number;
    averageDeviation: number;
  } {
    this.load();
    const entries = Array.from(this.calibrations.values());

    if (entries.length === 0) {
      return { totalFoods: 0, totalCorrections: 0, averageDeviation: 0 };
    }

    const totalCorrections = entries.reduce((sum, e) => sum + e.sampleCount, 0);
    const averageDeviation =
      entries.reduce((sum, e) => sum + Math.abs(e.correctionFactor - 1), 0) / entries.length;

    return {
      totalFoods: entries.length,
      totalCorrections,
      averageDeviation: Math.round(averageDeviation * 100)
    };
  }
}

export const calibrationStore = new CalibrationStore();
