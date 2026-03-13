/**
 * Recognition service interface and canonical types.
 * Defines the contract for food image analysis backends.
 */
import { MockRecognitionService } from "./mock-recognition.js";
import { HttpRecognitionService } from "./http-recognition.js";

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
 * Factory for creating the appropriate recognition service based on environment config.
 * Server-side only — reads from process.env.
 */
export function createRecognitionService(): IRecognitionService {
  if (process.env["RECOGNITION_MOCK_MODE"] === "true") {
    return new MockRecognitionService();
  }
  return new HttpRecognitionService();
}
