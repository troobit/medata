/**
 * Claude food recognition service implementation.
 * Req 2.1, 2.8: Send images to Claude API
 * Req 2.6: 10-second timeout (D-DES-013)
 * D-DES-001: Use structured JSON mode
 */
import Anthropic from '@anthropic-ai/sdk';
import type { RecognisedFoodItem, MacroData } from '$lib/types/index.js';
import {
	type IFoodRecognitionService,
	type FoodRecognitionResult,
	type LabelContext,
	FoodRecognitionError
} from './food-recognition.js';
import { sumMacros } from '$lib/utils/index.js';
import { env } from '$env/dynamic/private';

// Prompt templates from specs/ai-prompt-design.md
const FOOD_RECOGNITION_PROMPT = `You are a nutrition analysis assistant helping a person with Type 1 diabetes track their food intake. Your task is to identify foods in the image and estimate macronutrients as accurately as possible.

CONTEXT:
- The user needs accurate carbohydrate estimates for insulin dosing
- Precision matters more than conservative estimates
- The user is medically informed and does not need health disclaimers

ANALYSIS INSTRUCTIONS:

1. IDENTIFY each distinct food item visible in the image
2. ESTIMATE the portion size using visual cues:
   - Standard plate sizes (dinner plate ~26cm, side plate ~15cm)
   - Common reference objects if visible (cutlery, hands, cups)
   - Typical serving sizes for the identified food
3. CALCULATE macronutrients for each item based on portion estimate
4. ASSIGN a confidence score (0-1) reflecting:
   - Clarity of food identification (0.9+ if clearly visible)
   - Portion estimation certainty (reduce if size unclear)
   - Food preparation uncertainty (reduce if cooking method unclear)

PORTION ESTIMATION GUIDELINES:
- Use visual depth cues to estimate thickness/height of foods
- A closed fist is approximately 1 cup (240ml)
- A palm (no fingers) is approximately 85g of protein
- A thumb tip is approximately 1 tablespoon (15ml)
- Standard dinner plate diameter is 26cm
- Food near plate edge provides scale reference

OUTPUT FORMAT:
Return ONLY valid JSON matching this structure:
{
  "items": [
    {
      "name": "Food name",
      "quantity": 150,
      "unit": "g",
      "carbs": 25,
      "protein": 8,
      "fat": 12,
      "confidence": 0.85,
      "servingsEstimated": null
    }
  ],
  "overallConfidence": 0.85,
  "notes": "Optional observations"
}

All macro values in grams. Confidence between 0 and 1.`;

const FOOD_RECOGNITION_WITH_LABEL_PROMPT = `You are a nutrition analysis assistant helping a person with Type 1 diabetes track their food intake. You have TWO images:
1. A photograph of the food being consumed
2. A nutrition information label from the packaging

CONTEXT:
- The user needs accurate carbohydrate estimates for insulin dosing
- The label provides exact nutritional data per serving
- Your task is to estimate how many servings are shown in the food photo
- Australian nutrition labels show values per serving AND per 100g

ANALYSIS INSTRUCTIONS:

1. EXTRACT nutrition data from the label:
   - Identify "Per Serving" values (prioritise these)
   - Note the serving size stated on the label
   - Use "Per 100g" as a cross-reference

2. ANALYSE the food photograph:
   - Identify what portion of the package contents is shown
   - Estimate the number of servings visible
   - Note if the serving appears larger/smaller than the label's serving size

3. CALCULATE actual macros:
   - Multiply per-serving values by estimated servings
   - OR use per-100g values if weight can be estimated

4. ASSIGN confidence scores:
   - Higher (0.8+) if label is clear and portion matches stated serving
   - Medium (0.6-0.8) if estimating partial servings
   - Lower (<0.6) if label is unclear or portion is ambiguous

AUSTRALIAN LABEL FORMAT:
- "Servings per package" indicates total servings
- "Serving size" shows grams or ml per serving
- Columns: "Per Serving" and "Per 100g" (or "Per 100ml")
- Carbohydrates includes sugars as a sub-row
- Energy in kJ (divide by 4.18 for kcal if needed)

OUTPUT FORMAT:
Return ONLY valid JSON matching this structure:
{
  "items": [
    {
      "name": "Product name from label",
      "quantity": 1.5,
      "unit": "servings",
      "carbs": 45,
      "protein": 12,
      "fat": 8,
      "confidence": 0.90,
      "servingsEstimated": 1.5
    }
  ],
  "overallConfidence": 0.90,
  "notes": "Label states 30g per serving. Estimated 1.5 servings based on portion shown."
}

All macro values in grams. Include servingsEstimated when using label data.`;

// JSON schema for structured output
const FOOD_RECOGNITION_SCHEMA = {
	type: 'object',
	properties: {
		items: {
			type: 'array',
			items: {
				type: 'object',
				properties: {
					name: { type: 'string' },
					quantity: { type: 'number' },
					unit: { type: 'string' },
					carbs: { type: 'number' },
					protein: { type: 'number' },
					fat: { type: 'number' },
					confidence: { type: 'number' },
					servingsEstimated: { type: ['number', 'null'] }
				},
				required: ['name', 'quantity', 'unit', 'carbs', 'protein', 'fat', 'confidence'],
				additionalProperties: false
			}
		},
		overallConfidence: { type: 'number' },
		notes: { type: 'string' }
	},
	required: ['items', 'overallConfidence'],
	additionalProperties: false
};

interface ClaudeRecognitionResponse {
	items: Array<{
		name: string;
		quantity: number;
		unit: string;
		carbs: number;
		protein: number;
		fat: number;
		confidence: number;
		servingsEstimated: number | null;
	}>;
	overallConfidence: number;
	notes?: string;
}

/**
 * Convert a Blob to base64 string.
 */
async function blobToBase64(blob: Blob): Promise<string> {
	const buffer = await blob.arrayBuffer();
	const bytes = new Uint8Array(buffer);
	let binary = '';
	for (let i = 0; i < bytes.length; i++) {
		binary += String.fromCharCode(bytes[i]!);
	}
	return btoa(binary);
}

/**
 * Get MIME type for Claude API.
 */
function getMimeType(blob: Blob): 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp' {
	const type = blob.type;
	if (type === 'image/jpeg' || type === 'image/png' || type === 'image/gif' || type === 'image/webp') {
		return type;
	}
	// Default to JPEG
	return 'image/jpeg';
}

/**
 * Claude food recognition service.
 */
export class ClaudeFoodRecognitionService implements IFoodRecognitionService {
	private client: Anthropic | null = null;
	private readonly timeout = 10000; // Req 2.6: 10-second timeout

	constructor() {
		const apiKey = env['ANTHROPIC_API_KEY'];
		if (apiKey) {
			this.client = new Anthropic({
				apiKey
			});
		}
	}

	isConfigured(): boolean {
		return this.client !== null;
	}

	getProviderName(): string {
		return 'claude';
	}

	async recognise(image: Blob, labelContext?: LabelContext): Promise<FoodRecognitionResult> {
		if (!this.client) {
			throw new FoodRecognitionError('NOT_CONFIGURED', 'Claude API key not configured.');
		}

		const startTime = Date.now();
		const imageSize = (image.size / 1024).toFixed(1);
		console.log(`[claude] Starting recognition - food image: ${imageSize}KB${labelContext ? ', with label' : ''}`);

		// Build content array - images before text per best practices
		const content: Anthropic.MessageCreateParams['messages'][0]['content'] = [];

		// Add food image
		const foodImageBase64 = await blobToBase64(image);
		content.push({
			type: 'image',
			source: {
				type: 'base64',
				media_type: getMimeType(image),
				data: foodImageBase64
			}
		});

		// Add label image if provided
		if (labelContext?.labelImage) {
			const labelImageBase64 = await blobToBase64(labelContext.labelImage);
			content.push({
				type: 'image',
				source: {
					type: 'base64',
					media_type: getMimeType(labelContext.labelImage),
					data: labelImageBase64
				}
			});
		}

		// Add prompt text
		content.push({
			type: 'text',
			text: labelContext ? FOOD_RECOGNITION_WITH_LABEL_PROMPT : FOOD_RECOGNITION_PROMPT
		});

		try {
			// Create request with timeout
			const controller = new AbortController();
			const timeoutId = setTimeout(() => controller.abort(), this.timeout);

			const response = await this.client.messages.create(
				{
					model: 'claude-sonnet-4-5-20250514',
					max_tokens: 1024,
					messages: [
						{
							role: 'user',
							content
						}
					]
				},
				{
					signal: controller.signal
				}
			);

			clearTimeout(timeoutId);
			const apiTime = Date.now() - startTime;
			console.log(`[claude] API response received in ${apiTime}ms - tokens: ${response.usage.input_tokens}in/${response.usage.output_tokens}out`);

			// Extract JSON from response
			const textContent = response.content.find((c) => c.type === 'text');
			if (!textContent || textContent.type !== 'text') {
				throw new FoodRecognitionError('AI_FAILURE', 'No text response from AI.');
			}

			// Parse JSON response
			let parsed: ClaudeRecognitionResponse;
			try {
				// Try to extract JSON from the response (it may be wrapped in markdown code blocks)
				let jsonText = textContent.text;
				const jsonMatch = jsonText.match(/```(?:json)?\s*([\s\S]*?)```/);
				if (jsonMatch && jsonMatch[1]) {
					jsonText = jsonMatch[1].trim();
				}
				parsed = JSON.parse(jsonText);
			} catch {
				throw new FoodRecognitionError('AI_FAILURE', 'Invalid JSON response from AI.');
			}

			// Check for no items (Req 2.10)
			if (!parsed.items || parsed.items.length === 0) {
				throw new FoodRecognitionError(
					'NO_ITEMS',
					'No food items recognised. Retry or enter manually.'
				);
			}

			// Transform response to our format
			const items: RecognisedFoodItem[] = parsed.items.map((item) => ({
				name: item.name,
				quantity: item.quantity,
				unit: item.unit,
				carbs: Math.max(0, item.carbs),
				protein: Math.max(0, item.protein),
				fat: Math.max(0, item.fat),
				confidence: Math.min(1, Math.max(0, item.confidence))
			}));

			const totalMacros: MacroData = sumMacros(items);
			const processingTimeMs = Date.now() - startTime;
			console.log(`[claude] Recognition complete in ${processingTimeMs}ms - ${items.length} item(s), confidence: ${parsed.overallConfidence.toFixed(2)}`);

			return {
				items,
				totalMacros,
				confidence: Math.min(1, Math.max(0, parsed.overallConfidence)),
				provider: this.getProviderName(),
				processingTimeMs
			};
		} catch (error) {
			const elapsed = Date.now() - startTime;
			console.error(`[claude] Recognition failed after ${elapsed}ms:`, error instanceof Error ? error.message : error);

			// Handle timeout
			if (error instanceof Error && error.name === 'AbortError') {
				throw new FoodRecognitionError(
					'TIMEOUT',
					'Recognition timed out. Try again or enter manually.'
				);
			}

			// Re-throw FoodRecognitionErrors
			if (error instanceof FoodRecognitionError) {
				throw error;
			}

			// Wrap other errors
			throw new FoodRecognitionError(
				'AI_FAILURE',
				error instanceof Error ? error.message : 'AI recognition unavailable.'
			);
		}
	}
}
