/**
 * GET /api/meals/day/[date] endpoint
 * Per design section 4.4
 * Get meals for a specific day
 * Date format: YYYY-MM-DD
 */
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getMealRepository } from '$lib/repositories/index.js';

// Date format regex: YYYY-MM-DD
const DATE_REGEX = /^\d{4}-\d{2}-\d{2}$/;

export const GET: RequestHandler = async ({ params }) => {
	const { date } = params;

	// Validate date format
	if (!DATE_REGEX.test(date)) {
		return error(400, {
			message: 'Invalid date format. Use YYYY-MM-DD.'
		});
	}

	// Parse the date
	const parsedDate = new Date(date);
	if (isNaN(parsedDate.getTime())) {
		return error(400, {
			message: 'Invalid date. Check the date values.'
		});
	}

	// Get meals for the day
	try {
		const mealRepository = getMealRepository();
		const meals = await mealRepository.getByDay(parsedDate);

		return json({
			data: meals
		});
	} catch (e) {
		console.error('Get meals by day error:', e);
		return error(500, {
			message: 'Failed to retrieve meals. Try again.'
		});
	}
};
