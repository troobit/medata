/**
 * GET/PUT/DELETE /api/meals/[id] endpoint
 * Per design section 4.4
 * Get, update, or delete a meal by ID
 */
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { UpdateMealInputSchema } from '$lib/schemas/index.js';
import { getMealRepository } from '$lib/repositories/index.js';
import type { UpdateMealInput } from '$lib/types/index.js';

/**
 * GET /api/meals/[id]
 * Get a meal by ID
 */
export const GET: RequestHandler = async ({ params }) => {
	const { id } = params;

	try {
		const mealRepository = getMealRepository();
		const meal = await mealRepository.getById(id);

		if (!meal) {
			return error(404, {
				message: 'Meal not found.'
			});
		}

		return json({
			data: meal
		});
	} catch (e) {
		console.error('Get meal error:', e);
		return error(500, {
			message: 'Failed to retrieve meal. Try again.'
		});
	}
};

/**
 * PUT /api/meals/[id]
 * Update a meal
 * Req 8.4: Edit saved meals after storage
 */
export const PUT: RequestHandler = async ({ params, request }) => {
	const { id } = params;

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
	const parseResult = UpdateMealInputSchema.safeParse(body);
	if (!parseResult.success) {
		const firstError = parseResult.error.issues[0];
		return error(400, {
			message: `${firstError?.path.join('.') || 'Input'} is invalid. ${firstError?.message || ''}`
		});
	}

	// Build update input explicitly to handle optional fields
	const data = parseResult.data;
	const updates: UpdateMealInput = {};

	if (data.timestamp !== undefined) {
		updates.timestamp = data.timestamp;
	}
	if (data.items !== undefined) {
		updates.items = data.items;
	}
	if (data.totalCarbs !== undefined) {
		updates.totalCarbs = data.totalCarbs;
	}
	if (data.totalProtein !== undefined) {
		updates.totalProtein = data.totalProtein;
	}
	if (data.totalFat !== undefined) {
		updates.totalFat = data.totalFat;
	}
	if (data.imageUrl !== undefined) {
		updates.imageUrl = data.imageUrl;
	}

	// Update the meal
	try {
		const mealRepository = getMealRepository();
		const meal = await mealRepository.update(id, updates);

		return json({
			data: meal
		});
	} catch (e) {
		if (e instanceof Error && e.message.includes('not found')) {
			return error(404, {
				message: 'Meal not found.'
			});
		}
		console.error('Update meal error:', e);
		return error(500, {
			message: 'Update failed. Try again.'
		});
	}
};

/**
 * DELETE /api/meals/[id]
 * Delete a meal
 * Req 8.5: Delete from logbook
 */
export const DELETE: RequestHandler = async ({ params }) => {
	const { id } = params;

	try {
		const mealRepository = getMealRepository();
		await mealRepository.delete(id);

		return json({
			data: { success: true }
		});
	} catch (e) {
		if (e instanceof Error && e.message.includes('not found')) {
			return error(404, {
				message: 'Meal not found.'
			});
		}
		console.error('Delete meal error:', e);
		return error(500, {
			message: 'Delete failed. Try again.'
		});
	}
};
