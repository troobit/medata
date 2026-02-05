/**
 * POST /api/ai/recognise endpoint
 * Per design section 4.4
 * Accept imageBase64 and mimeType
 * Return items, totalMacros, confidence, provider, processingTimeMs
 * Handle timeout and errors per design section 5.1
 */
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod/v4';
import { ClaudeFoodRecognitionService, FoodRecognitionError } from '$lib/services/index.js';

// Request schema per design section 4.4
const RecogniseRequestSchema = z.object({
	imageBase64: z.string().min(1),
	mimeType: z.enum(['image/jpeg', 'image/png']),
	// Optional label image for packaged foods
	labelBase64: z.string().optional(),
	labelMimeType: z.enum(['image/jpeg', 'image/png']).optional()
});

/**
 * Convert base64 string to Blob.
 */
function base64ToBlob(base64: string, mimeType: string): Blob {
	const binaryString = atob(base64);
	const bytes = new Uint8Array(binaryString.length);
	for (let i = 0; i < binaryString.length; i++) {
		bytes[i] = binaryString.charCodeAt(i);
	}
	return new Blob([bytes], { type: mimeType });
}

export const POST: RequestHandler = async ({ request }) => {
	// Parse and validate request body
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return error(400, {
			message: 'Invalid JSON in request body.'
		});
	}

	const parseResult = RecogniseRequestSchema.safeParse(body);
	if (!parseResult.success) {
		const firstError = parseResult.error.issues[0];
		return error(400, {
			message: `${firstError?.path.join('.') || 'Input'} is invalid. ${firstError?.message || ''}`
		});
	}

	const { imageBase64, mimeType, labelBase64, labelMimeType } = parseResult.data;

	// Create food recognition service
	const service = new ClaudeFoodRecognitionService();

	// Check if service is configured
	if (!service.isConfigured()) {
		return error(503, {
			message: 'AI recognition unavailable. Enter macros manually.'
		});
	}

	// Convert base64 to Blob
	let foodImage: Blob;
	try {
		foodImage = base64ToBlob(imageBase64, mimeType);
	} catch {
		return error(400, {
			message: 'Invalid image data. Please try again.'
		});
	}

	// Convert label image if provided
	let labelContext: { labelImage: Blob } | undefined;
	if (labelBase64 && labelMimeType) {
		try {
			labelContext = {
				labelImage: base64ToBlob(labelBase64, labelMimeType)
			};
		} catch {
			return error(400, {
				message: 'Invalid label image data. Please try again.'
			});
		}
	}

	// Perform recognition
	try {
		const result = await service.recognise(foodImage, labelContext);

		return json({
			data: {
				items: result.items,
				totalMacros: result.totalMacros,
				confidence: result.confidence,
				provider: result.provider,
				processingTimeMs: result.processingTimeMs
			}
		});
	} catch (e) {
		if (e instanceof FoodRecognitionError) {
			switch (e.code) {
				case 'TIMEOUT':
					// Req 2.6: 10-second timeout
					return error(504, {
						message: 'Recognition timed out. Try again or enter manually.'
					});
				case 'NO_ITEMS':
					// Req 2.10: Zero items recognised
					return error(422, {
						message: 'No food items recognised. Retry or enter manually.'
					});
				case 'NOT_CONFIGURED':
					return error(503, {
						message: 'AI recognition unavailable. Enter macros manually.'
					});
				case 'INVALID_IMAGE':
					return error(400, {
						message: 'Invalid image format. Use JPEG or PNG.'
					});
				default:
					// AI_FAILURE
					return error(502, {
						message: 'AI recognition unavailable. Enter macros manually.'
					});
			}
		}

		// Unknown error
		console.error('Food recognition error:', e);
		return error(500, {
			message: 'Recognition failed. Try again.'
		});
	}
};
