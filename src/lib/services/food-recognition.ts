/**
 * Food recognition service interface and types.
 * Per design section 3.3.
 */
import type { RecognisedFoodItem, MacroData } from '$lib/types/index.js';

/**
 * Optional context from a nutrition label scan.
 * Used to improve accuracy for packaged foods.
 */
export interface LabelContext {
	labelImage: Blob; // The label photo for OCR
}

/**
 * Result of food recognition from AI.
 */
export interface FoodRecognitionResult {
	items: RecognisedFoodItem[];
	totalMacros: MacroData;
	confidence: number; // Overall confidence 0-1
	provider: string; // e.g., 'claude', 'openai', 'gemini'
	processingTimeMs: number;
}

/**
 * Error codes for food recognition failures.
 */
export type FoodRecognitionErrorCode =
	| 'TIMEOUT' // Req 2.6: 10-second timeout
	| 'AI_FAILURE' // Req 2.7: AI service unavailable
	| 'NO_ITEMS' // Req 2.10: Zero items recognised
	| 'NOT_CONFIGURED' // AI provider not configured
	| 'INVALID_IMAGE'; // Image format not supported

/**
 * Error thrown by food recognition service.
 */
export class FoodRecognitionError extends Error {
	constructor(
		public readonly code: FoodRecognitionErrorCode,
		message: string
	) {
		super(message);
		this.name = 'FoodRecognitionError';
	}
}

/**
 * Interface for food recognition services.
 * Per design section 3.3.
 * Req 2.1-2.10
 */
export interface IFoodRecognitionService {
	/**
	 * Recognise food items in an image.
	 *
	 * @param image - The food image to analyse
	 * @param labelContext - Optional nutrition label context for improved accuracy
	 * @returns Recognition result with food items and macros
	 * @throws FoodRecognitionError on timeout, failure, or no items
	 */
	recognise(image: Blob, labelContext?: LabelContext): Promise<FoodRecognitionResult>;

	/**
	 * Check if the service is properly configured.
	 * @returns true if API keys and settings are configured
	 */
	isConfigured(): boolean;

	/**
	 * Get the name of the AI provider.
	 * @returns Provider name (e.g., 'claude', 'openai')
	 */
	getProviderName(): string;
}
