/**
 * Integration tests for meal repository.
 * Per design section 6.4
 * These tests validate the repository contract.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { IMealRepository } from './meal-repository.js';
import type { Meal, CreateMealInput, UpdateMealInput } from '$lib/types/index.js';

/**
 * In-memory implementation for testing.
 * Matches the IMealRepository interface.
 */
class InMemoryMealRepository implements IMealRepository {
	private meals: Map<string, Meal> = new Map();
	private idCounter = 0;

	async create(input: CreateMealInput): Promise<Meal> {
		const id = `test-meal-${++this.idCounter}`;
		const now = Date.now();

		const meal: Meal = {
			id,
			timestamp: input.timestamp,
			items: input.items,
			totalCarbs: input.totalCarbs,
			totalProtein: input.totalProtein,
			totalFat: input.totalFat,
			source: input.source,
			createdAt: now,
			updatedAt: now
		};

		// Only add optional fields if they exist
		if (input.imageUrl !== undefined) {
			meal.imageUrl = input.imageUrl;
		}
		if (input.confidence !== undefined) {
			meal.confidence = input.confidence;
		}

		this.meals.set(id, meal);
		return meal;
	}

	async getById(id: string): Promise<Meal | null> {
		return this.meals.get(id) ?? null;
	}

	async getByDay(date: Date): Promise<Meal[]> {
		const dayStart = new Date(date);
		dayStart.setHours(0, 0, 0, 0);
		const dayEnd = new Date(date);
		dayEnd.setHours(23, 59, 59, 999);

		return Array.from(this.meals.values())
			.filter((meal) => {
				const mealDate = new Date(meal.timestamp);
				return mealDate >= dayStart && mealDate <= dayEnd;
			})
			.sort((a, b) => b.timestamp - a.timestamp);
	}

	async getByDateRange(start: Date, end: Date): Promise<Meal[]> {
		const startTimestamp = start.setHours(0, 0, 0, 0);
		const endTimestamp = end.setHours(23, 59, 59, 999);

		return Array.from(this.meals.values())
			.filter((meal) => meal.timestamp >= startTimestamp && meal.timestamp <= endTimestamp)
			.sort((a, b) => b.timestamp - a.timestamp);
	}

	async update(id: string, updates: UpdateMealInput): Promise<Meal> {
		const existing = this.meals.get(id);
		if (!existing) {
			throw new Error(`Meal with id ${id} not found`);
		}

		const updated: Meal = {
			...existing,
			updatedAt: Date.now()
		};

		// Apply updates explicitly to avoid undefined assignment issues
		if (updates.timestamp !== undefined) {
			updated.timestamp = updates.timestamp;
		}
		if (updates.items !== undefined) {
			updated.items = updates.items;
		}
		if (updates.totalCarbs !== undefined) {
			updated.totalCarbs = updates.totalCarbs;
		}
		if (updates.totalProtein !== undefined) {
			updated.totalProtein = updates.totalProtein;
		}
		if (updates.totalFat !== undefined) {
			updated.totalFat = updates.totalFat;
		}
		if (updates.imageUrl !== undefined) {
			updated.imageUrl = updates.imageUrl;
		}

		this.meals.set(id, updated);
		return updated;
	}

	async delete(id: string): Promise<void> {
		if (!this.meals.has(id)) {
			throw new Error(`Meal with id ${id} not found`);
		}
		this.meals.delete(id);
	}

	// Helper for tests
	clear() {
		this.meals.clear();
		this.idCounter = 0;
	}
}

describe('IMealRepository', () => {
	let repository: InMemoryMealRepository;

	beforeEach(() => {
		repository = new InMemoryMealRepository();
	});

	const createTestMealInput = (overrides: Partial<CreateMealInput> = {}): CreateMealInput => ({
		timestamp: Date.now(),
		items: [{ name: 'Test Food', carbs: 10, protein: 5, fat: 3 }],
		totalCarbs: 10,
		totalProtein: 5,
		totalFat: 3,
		source: 'manual',
		...overrides
	});

	describe('create', () => {
		it('creates a meal and returns it with generated id', async () => {
			const input = createTestMealInput();

			const meal = await repository.create(input);

			expect(meal.id).toBeDefined();
			expect(meal.timestamp).toBe(input.timestamp);
			expect(meal.items).toEqual(input.items);
			expect(meal.totalCarbs).toBe(input.totalCarbs);
			expect(meal.totalProtein).toBe(input.totalProtein);
			expect(meal.totalFat).toBe(input.totalFat);
			expect(meal.source).toBe(input.source);
		});

		it('sets createdAt and updatedAt timestamps', async () => {
			const beforeCreate = Date.now();
			const meal = await repository.create(createTestMealInput());
			const afterCreate = Date.now();

			expect(meal.createdAt).toBeGreaterThanOrEqual(beforeCreate);
			expect(meal.createdAt).toBeLessThanOrEqual(afterCreate);
			expect(meal.updatedAt).toBe(meal.createdAt);
		});

		it('stores optional imageUrl', async () => {
			const input = createTestMealInput({ imageUrl: 'https://example.com/image.jpg' });

			const meal = await repository.create(input);

			expect(meal.imageUrl).toBe('https://example.com/image.jpg');
		});

		it('stores optional confidence', async () => {
			const input = createTestMealInput({ confidence: 0.85 });

			const meal = await repository.create(input);

			expect(meal.confidence).toBe(0.85);
		});
	});

	describe('getById', () => {
		it('returns meal when found', async () => {
			const created = await repository.create(createTestMealInput());

			const found = await repository.getById(created.id);

			expect(found).toEqual(created);
		});

		it('returns null when not found', async () => {
			const found = await repository.getById('non-existent-id');

			expect(found).toBeNull();
		});
	});

	describe('getByDay', () => {
		it('returns meals for the specified day', async () => {
			const today = new Date();
			const todayNoon = new Date(today);
			todayNoon.setHours(12, 0, 0, 0);

			const yesterday = new Date(today);
			yesterday.setDate(yesterday.getDate() - 1);

			// Create meals for today and yesterday
			const todayMeal = await repository.create(
				createTestMealInput({ timestamp: todayNoon.getTime() })
			);
			await repository.create(createTestMealInput({ timestamp: yesterday.getTime() }));

			const meals = await repository.getByDay(today);

			expect(meals).toHaveLength(1);
			expect(meals[0]!.id).toBe(todayMeal.id);
		});

		it('returns meals sorted by timestamp descending', async () => {
			const today = new Date();
			const morning = new Date(today);
			morning.setHours(8, 0, 0, 0);
			const evening = new Date(today);
			evening.setHours(20, 0, 0, 0);

			await repository.create(createTestMealInput({ timestamp: morning.getTime() }));
			await repository.create(createTestMealInput({ timestamp: evening.getTime() }));

			const meals = await repository.getByDay(today);

			expect(meals).toHaveLength(2);
			expect(meals[0]!.timestamp).toBeGreaterThan(meals[1]!.timestamp);
		});

		it('returns empty array when no meals for day', async () => {
			const meals = await repository.getByDay(new Date());

			expect(meals).toHaveLength(0);
		});
	});

	describe('getByDateRange', () => {
		it('returns meals within the date range', async () => {
			const today = new Date();
			const yesterday = new Date(today);
			yesterday.setDate(yesterday.getDate() - 1);
			const twoDaysAgo = new Date(today);
			twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);

			await repository.create(createTestMealInput({ timestamp: today.getTime() }));
			await repository.create(createTestMealInput({ timestamp: yesterday.getTime() }));
			await repository.create(createTestMealInput({ timestamp: twoDaysAgo.getTime() }));

			const meals = await repository.getByDateRange(yesterday, today);

			expect(meals).toHaveLength(2);
		});
	});

	describe('update', () => {
		it('updates meal and returns updated version', async () => {
			const created = await repository.create(createTestMealInput());

			const updated = await repository.update(created.id, {
				items: [{ name: 'Updated Food', carbs: 20, protein: 10, fat: 6 }],
				totalCarbs: 20,
				totalProtein: 10,
				totalFat: 6
			});

			expect(updated.items[0]!.name).toBe('Updated Food');
			expect(updated.totalCarbs).toBe(20);
		});

		it('updates updatedAt timestamp', async () => {
			const created = await repository.create(createTestMealInput());

			// Wait a bit to ensure different timestamp
			await new Promise((resolve) => setTimeout(resolve, 10));

			const updated = await repository.update(created.id, { totalCarbs: 15 });

			expect(updated.updatedAt).toBeGreaterThan(created.updatedAt);
		});

		it('preserves unchanged fields', async () => {
			const input = createTestMealInput({
				imageUrl: 'https://example.com/image.jpg',
				confidence: 0.85
			});
			const created = await repository.create(input);

			const updated = await repository.update(created.id, { totalCarbs: 15 });

			expect(updated.imageUrl).toBe('https://example.com/image.jpg');
			expect(updated.confidence).toBe(0.85);
			expect(updated.source).toBe('manual');
		});

		it('throws error when meal not found', async () => {
			await expect(repository.update('non-existent-id', { totalCarbs: 15 })).rejects.toThrow(
				'not found'
			);
		});
	});

	describe('delete', () => {
		it('removes meal from storage', async () => {
			const created = await repository.create(createTestMealInput());

			await repository.delete(created.id);

			const found = await repository.getById(created.id);
			expect(found).toBeNull();
		});

		it('throws error when meal not found', async () => {
			await expect(repository.delete('non-existent-id')).rejects.toThrow('not found');
		});
	});
});
