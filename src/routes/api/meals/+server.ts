/**
 * POST /api/meals endpoint
 * Per design section 4.4
 * Create a new meal
 * Returns 201 with the created meal
 */
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { CreateMealInputSchema } from '$lib/schemas/index.js';
import { getMealRepository } from '$lib/repositories/index.js';
import type { CreateMealInput } from '$lib/types/index.js';

export const POST: RequestHandler = async ({ request }) => {
	// Parse request body
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		return error(400, {
			message: 'Invalid JSON in request body.'
		});
	}

	// Validate input
	const parseResult = CreateMealInputSchema.safeParse(body);
	if (!parseResult.success) {
		const firstError = parseResult.error.issues[0];
		return error(400, {
			message: `${firstError?.path.join('.') || 'Input'} is invalid. ${firstError?.message || ''}`
		});
	}

	// Build the meal input explicitly to handle optional fields
	const data = parseResult.data;
	const mealInput: CreateMealInput = {
		timestamp: data.timestamp,
		items: data.items,
		totalCarbs: data.totalCarbs,
		totalProtein: data.totalProtein,
		totalFat: data.totalFat,
		source: data.source
	};

	if (data.imageUrl !== undefined) {
		mealInput.imageUrl = data.imageUrl;
	}
	if (data.confidence !== undefined) {
		mealInput.confidence = data.confidence;
	}

	// Create the meal
	try {
		const mealRepository = getMealRepository();
		const meal = await mealRepository.create(mealInput);

		return json(
			{
				data: meal
			},
			{ status: 201 }
		);
	} catch (e) {
		console.error('Meal creation error:', e);
		return error(500, {
			message: 'Save failed. Try again.'
		});
	}
};
