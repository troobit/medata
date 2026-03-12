/**
 * Recognition service interface and canonical types.
 * Defines the contract for food image analysis backends.
 */

/**
 * Interface for food recognition services.
 */
export interface IRecognitionService {
  analyse(image: Blob): Promise<FoodAnalysisResult>;
  isReady(): boolean;
  getBackendType(): string;
}

/**
 * Result of food image analysis.
 */
export interface FoodAnalysisResult {
  items: AnalysedFoodItem[];
  overallConfidence: number;
  notes?: string;
}

/**
 * A single food item identified by analysis.
 */
export interface AnalysedFoodItem {
  name: string;
  carbs: number;
  protein: number;
  fat: number;
  confidence: number;
}

/**
 * Error codes for recognition failures.
 */
export type RecognitionErrorCode =
  | "TIMEOUT"
  | "NOT_CONFIGURED"
  | "BACKEND_ERROR"
  | "INVALID_RESPONSE"
  | "NO_ITEMS";

/**
 * Error thrown by recognition services.
 */
export class RecognitionError extends Error {
  constructor(
    public readonly code: RecognitionErrorCode,
    public readonly httpStatus?: number,
  ) {
    super(
      `RecognitionError: ${code}${httpStatus ? ` (HTTP ${httpStatus})` : ""}`,
    );
    this.name = "RecognitionError";
  }
}

/**
 * Factory stub for creating a recognition service.
 * Will be implemented in a later task.
 */
export function createRecognitionService(): IRecognitionService {
  throw new Error("createRecognitionService() not yet implemented");
}
