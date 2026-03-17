/**
 * Meal repository interface.
 * Per design section 3.3.
 * Req 4.1-4.8, 8.4, 8.5
 */
import type { Meal, CreateMealInput, UpdateMealInput } from '$lib/types/index.js';

/**
 * Interface for meal data persistence.
 * Implements repository pattern for data access abstraction.
 */
export interface IMealRepository {
	/**
	 * Create a new meal record.
	 * Req 4.1: Persist with timestamp, items, totals, source, and optional imageUrl.
	 * Req 10.1, 10.2: Sets createdAt and updatedAt timestamps.
	 *
	 * @param meal - The meal data to create
	 * @returns The created meal with generated id and timestamps
	 */
	create(meal: CreateMealInput): Promise<Meal>;

	/**
	 * Get a meal by its ID.
	 *
	 * @param id - The meal ID
	 * @returns The meal if found, null otherwise
	 */
	getById(id: string): Promise<Meal | null>;

	/**
	 * Get all meals for a specific day.
	 * Per design D-DES-007: Day-based pagination.
	 *
	 * @param date - The date to query (uses YYYY-MM-DD partition key)
	 * @returns Array of meals for that day, sorted by timestamp descending
	 */
	getByDay(date: Date): Promise<Meal[]>;

	/**
	 * Get meals within a date range.
	 *
	 * @param start - Start date (inclusive)
	 * @param end - End date (inclusive)
	 * @returns Array of meals in the range, sorted by timestamp descending
	 */
	getByDateRange(start: Date, end: Date): Promise<Meal[]>;

	/**
	 * Update an existing meal.
	 * Req 8.4: Edit saved meals after storage.
	 * Req 10.2: Updates the updatedAt timestamp.
	 *
	 * @param id - The meal ID to update
	 * @param updates - The fields to update
	 * @returns The updated meal
	 * @throws Error if meal not found
	 */
	update(id: string, updates: UpdateMealInput): Promise<Meal>;

	/**
	 * Delete a meal.
	 * Req 8.5: Delete from logbook.
	 * Req 4.8: Never delete without explicit user action.
	 *
	 * @param id - The meal ID to delete
	 * @throws Error if meal not found
	 */
	delete(id: string): Promise<void>;
}
