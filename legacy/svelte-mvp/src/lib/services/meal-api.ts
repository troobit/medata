/**
 * Client-side meal API service.
 * Handles API calls to meal endpoints.
 */
import type { Meal, CreateMealInput, UpdateMealInput } from '$lib/types/index.js';

/**
 * API response wrapper.
 */
interface ApiResponse<T> {
	data: T;
}

/**
 * API error response.
 */
interface ApiError {
	message: string;
}

/**
 * Create a new meal.
 * POST /api/meals
 */
export async function createMeal(input: CreateMealInput): Promise<Meal> {
	const response = await fetch('/api/meals', {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(input)
	});

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to create meal');
	}

	const { data }: ApiResponse<Meal> = await response.json();
	return data;
}

/**
 * Get a meal by ID.
 * GET /api/meals/[id]
 */
export async function getMealById(id: string): Promise<Meal | null> {
	const response = await fetch(`/api/meals/${id}`);

	if (response.status === 404) {
		return null;
	}

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to get meal');
	}

	const { data }: ApiResponse<Meal> = await response.json();
	return data;
}

/**
 * Get meals for a specific day.
 * GET /api/meals/day/[date]
 */
export async function getMealsByDay(date: Date): Promise<Meal[]> {
	const dateStr = date.toISOString().split('T')[0];
	const response = await fetch(`/api/meals/day/${dateStr}`);

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to get meals');
	}

	const { data }: ApiResponse<Meal[]> = await response.json();
	return data;
}

/**
 * Update an existing meal.
 * PUT /api/meals/[id]
 * Req 8.4: Edit saved meals after storage
 */
export async function updateMeal(id: string, updates: UpdateMealInput): Promise<Meal> {
	const response = await fetch(`/api/meals/${id}`, {
		method: 'PUT',
		headers: {
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(updates)
	});

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to update meal');
	}

	const { data }: ApiResponse<Meal> = await response.json();
	return data;
}

/**
 * Delete a meal.
 * DELETE /api/meals/[id]
 * Req 8.5: Delete from logbook
 */
export async function deleteMeal(id: string): Promise<void> {
	const response = await fetch(`/api/meals/${id}`, {
		method: 'DELETE'
	});

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to delete meal');
	}
}

/**
 * Upload an image.
 * POST /api/images/upload
 */
export async function uploadImage(
	image: File,
	folder: 'meals' | 'labels' = 'meals'
): Promise<string> {
	const formData = new FormData();
	formData.append('image', image);
	formData.append('folder', folder);

	const response = await fetch('/api/images/upload', {
		method: 'POST',
		body: formData
	});

	if (!response.ok) {
		const error: ApiError = await response.json();
		throw new Error(error.message || 'Failed to upload image');
	}

	const { data }: ApiResponse<{ imageUrl: string }> = await response.json();
	return data.imageUrl;
}
