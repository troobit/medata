/**
 * Workstream A: AI Food Recognition Types
 * Owner: workstream-a/food-ai branch
 *
 * This file defines types for cloud-based food recognition services.
 * Implementations should be added to src/lib/services/ai/
 */

import type { MacroData, MealItem } from './events';

/**
 * Bounding box for visual annotation of Recognised food
 */
export interface BoundingBox {
  x: number; // top-left x (0-1 normalized)
  y: number; // top-left y (0-1 normalized)
  width: number; // width (0-1 normalized)
  height: number; // height (0-1 normalized)
}

/**
 * Individual food item Recognised by AI
 */
export interface RecognisedFoodItem extends MealItem {
  confidence: number; // 0-1
  boundingBox?: BoundingBox;
  usdaFoodCode?: string; // USDA FNDDS reference
}

/**
 * Result from food recognition service
 */
export interface FoodRecognitionResult {
  items: RecognisedFoodItem[];
  totalMacros: MacroData;
  confidence: number; // overall confidence 0-1
  boundingBoxes?: BoundingBox[];
  rawResponse?: string; // for debugging
  provider: string; // which AI provider was used
  processingTimeMs: number;
}

/**
 * Result from nutrition label scanning
 */
export interface NutritionLabelResult {
  servingSize?: string;
  servingsPerContainer?: number;
  macros: Partial<MacroData>;
  fiber?: number;
  sugar?: number;
  sodium?: number;
  confidence: number;
}

/**
 * Options for food recognition
 */
export interface RecognitionOptions {
  includeAnnotations?: boolean;
  referenceObjectSize?: number; // known size in mm for scale
  preferredUnits?: 'metric' | 'imperial';
}

/**
 * Interface that all AI food recognition services must implement
 * Implementations: AzureFoundryFoodService, OpenAIFoodService, GeminiFoodService,
 *                  ClaudeFoodService, AzureFoodService, BedrockFoodService, LocalFoodService
 */
export interface IFoodRecognitionService {
  RecogniseFood(image: Blob, options?: RecognitionOptions): Promise<FoodRecognitionResult>;
  parseNutritionLabel(image: Blob): Promise<NutritionLabelResult>;
  isConfigured(): boolean;
  getProviderName(): string;
}
