/**
 * AI Model Validation Types
 * Used for collecting test data and measuring AI food recognition accuracy
 */

import type { MacroData, MealDataSource } from './events';
import type { RecognisedFoodItem } from './ai';

/**
 * Food category for grouping accuracy metrics
 */
export type FoodCategory =
  | 'grain'
  | 'protein'
  | 'vegetable'
  | 'fruit'
  | 'dairy'
  | 'fat'
  | 'beverage'
  | 'mixed'
  | 'snack'
  | 'other';

/**
 * Source of ground truth data
 */
export type GroundTruthSource =
  | 'usda'
  | 'academic'
  | 'nutrition-label'
  | 'manual-weighed'
  | 'imported';

/**
 * Test dataset entry - food image with known nutritional values
 */
export interface TestDatasetEntry {
  id: string;
  imageUrl: string; // Data URL (base64) or external URL
  groundTruth: MacroData;
  category?: FoodCategory;
  description?: string;
  source: GroundTruthSource;
  sourceReference?: string; // USDA code, paper DOI, etc.
  items?: Array<{
    name: string;
    quantity: number;
    unit: string;
    macros: Partial<MacroData>;
  }>;
  referenceObjects?: string[]; // e.g., ['credit-card', 'coin']
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Result of validating AI prediction against ground truth
 */
export interface ValidationResult {
  testEntryId: string;
  aiProvider: string;
  predictedMacros: MacroData;
  groundTruth: MacroData;
  predictedItems?: RecognisedFoodItem[];
  confidence: number;
  processingTimeMs: number;
  // Error metrics
  mae: MacroErrorMetrics; // Mean Absolute Error per field
  mape: MacroErrorMetrics; // Mean Absolute Percentage Error per field
  timestamp: Date;
}

/**
 * Error metrics for each macro field
 */
export interface MacroErrorMetrics {
  calories: number;
  carbs: number;
  protein: number;
  fat: number;
  overall: number; // Weighted average
}

/**
 * Aggregated accuracy metrics for a provider/category
 */
export interface AccuracyMetrics {
  provider: string;
  category?: FoodCategory;
  sampleCount: number;
  mae: MacroErrorMetrics;
  mape: MacroErrorMetrics;
  avgConfidence: number;
  avgProcessingTimeMs: number;
  period?: {
    start: Date;
    end: Date;
  };
}

/**
 * Correction history entry for learning from user edits
 */
export interface CorrectionHistoryEntry {
  id: string;
  eventId: string; // Reference to original PhysiologicalEvent
  imageUrl?: string;
  aiPrediction: MacroData;
  userCorrection: MacroData;
  aiItems?: RecognisedFoodItem[];
  correctedItems?: Array<{
    name: string;
    quantity: number;
    unit: string;
    macros: Partial<MacroData>;
  }>;
  aiProvider: string;
  aiConfidence: number;
  category?: FoodCategory;
  source: MealDataSource;
  timestamp: Date;
}

/**
 * Summary statistics for correction patterns
 */
export interface CorrectionPatternStats {
  category: FoodCategory;
  avgOverestimation: MacroErrorMetrics; // Positive = AI overestimates
  avgUnderestimation: MacroErrorMetrics; // Negative = AI underestimates
  correctionCount: number;
  avgConfidenceWhenWrong: number;
}

/**
 * Prompt enhancement suggestion based on correction patterns
 */
export interface PromptEnhancement {
  category: FoodCategory;
  adjustment: 'increase' | 'decrease';
  field: keyof MacroData;
  percentageAdjustment: number;
  confidence: number; // How confident we are in this suggestion
  sampleSize: number;
}

/**
 * Input for creating a test dataset entry
 */
export type CreateTestDataInput = Omit<TestDatasetEntry, 'id' | 'createdAt' | 'updatedAt'>;

/**
 * Input for updating a test dataset entry
 */
export type UpdateTestDataInput = Partial<Omit<TestDatasetEntry, 'id' | 'createdAt'>>;

/**
 * Export format for test datasets
 */
export interface TestDatasetExport {
  version: string;
  exportedAt: string;
  count: number;
  entries: TestDatasetEntry[];
  metadata?: {
    sources: GroundTruthSource[];
    categories: FoodCategory[];
  };
}

/**
 * Import format for USDA FNDDS data
 */
export interface USDAFoodEntry {
  fdcId: number;
  description: string;
  dataType: string;
  nutrients: Array<{
    nutrientId: number;
    nutrientName: string;
    amount: number;
    unitName: string;
  }>;
  portions?: Array<{
    portionDescription: string;
    gramWeight: number;
  }>;
}

/**
 * Import result for nutrition datasets
 */
export interface DatasetImportResult {
  success: boolean;
  imported: number;
  skipped: number;
  errors: Array<{
    line: number;
    message: string;
  }>;
}
