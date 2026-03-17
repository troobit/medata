/**
 * Integration tests for meal creation flow.
 * Per design section 6.3-6.4 and task 26.
 */
import { describe, it, expect } from 'vitest';
import {
	CreateMealInputSchema,
	FoodItemSchema,
	MealSchema,
	MacroDataSchema
} from './meal.js';
import { sumMacros } from '$lib/utils/macros.js';

describe('FoodItemSchema', () => {
	it('rejects negative carbs', () => {
		const result = FoodItemSchema.safeParse({
			name: 'Test Food',
			carbs: -5,
			protein: 10,
			fat: 5
		});
		expect(result.success).toBe(false);
	});

	it('rejects negative protein', () => {
		const result = FoodItemSchema.safeParse({
			name: 'Test Food',
			carbs: 10,
			protein: -5,
			fat: 5
		});
		expect(result.success).toBe(false);
	});

	it('rejects negative fat', () => {
		const result = FoodItemSchema.safeParse({
			name: 'Test Food',
			carbs: 10,
			protein: 5,
			fat: -5
		});
		expect(result.success).toBe(false);
	});

	it('accepts zero values', () => {
		const result = FoodItemSchema.safeParse({
			name: 'Test Food',
			carbs: 0,
			protein: 0,
			fat: 0
		});
		expect(result.success).toBe(true);
	});

	it('accepts valid food item', () => {
		const result = FoodItemSchema.safeParse({
			name: 'Eggs',
			carbs: 2,
			protein: 13,
			fat: 11
		});
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.name).toBe('Eggs');
			expect(result.data.carbs).toBe(2);
		}
	});

	it('rejects empty name', () => {
		const result = FoodItemSchema.safeParse({
			name: '',
			carbs: 10,
			protein: 5,
			fat: 5
		});
		expect(result.success).toBe(false);
	});
});

describe('CreateMealInputSchema', () => {
	it('rejects negative total macros', () => {
		const result = CreateMealInputSchema.safeParse({
			timestamp: Date.now(),
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: -1,
			totalProtein: 5,
			totalFat: 5,
			source: 'manual'
		});
		expect(result.success).toBe(false);
	});

	it('rejects empty items array', () => {
		const result = CreateMealInputSchema.safeParse({
			timestamp: Date.now(),
			items: [],
			totalCarbs: 0,
			totalProtein: 0,
			totalFat: 0,
			source: 'manual'
		});
		expect(result.success).toBe(false);
	});

	it('accepts valid meal input', () => {
		const items = [
			{ name: 'Scrambled Eggs', carbs: 2, protein: 13, fat: 11 },
			{ name: 'Toast', carbs: 25, protein: 4, fat: 2 }
		];
		const totals = sumMacros(items);

		const result = CreateMealInputSchema.safeParse({
			timestamp: Date.now(),
			items,
			totalCarbs: totals.carbs,
			totalProtein: totals.protein,
			totalFat: totals.fat,
			source: 'ai_image',
			confidence: 0.85
		});

		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data.totalCarbs).toBe(27);
			expect(result.data.totalProtein).toBe(17);
			expect(result.data.totalFat).toBe(13);
		}
	});

	it('accepts all valid source types', () => {
		const baseInput = {
			timestamp: Date.now(),
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5
		};

		const sources = ['manual', 'ai_image', 'preset'] as const;
		for (const source of sources) {
			const result = CreateMealInputSchema.safeParse({ ...baseInput, source });
			expect(result.success).toBe(true);
		}
	});

	it('rejects invalid source type', () => {
		const result = CreateMealInputSchema.safeParse({
			timestamp: Date.now(),
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5,
			source: 'invalid_source'
		});
		expect(result.success).toBe(false);
	});

	it('accepts optional imageUrl', () => {
		const result = CreateMealInputSchema.safeParse({
			timestamp: Date.now(),
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5,
			source: 'ai_image',
			imageUrl: 'https://example.com/image.jpg'
		});
		expect(result.success).toBe(true);
	});

	it('accepts optional confidence', () => {
		const result = CreateMealInputSchema.safeParse({
			timestamp: Date.now(),
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5,
			source: 'ai_image',
			confidence: 0.95
		});
		expect(result.success).toBe(true);
	});

	it('rejects confidence outside 0-1 range', () => {
		const result = CreateMealInputSchema.safeParse({
			timestamp: Date.now(),
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5,
			source: 'ai_image',
			confidence: 1.5
		});
		expect(result.success).toBe(false);
	});
});

describe('MealSchema timestamp validation', () => {
	it('accepts timestamp as UTC Unix milliseconds', () => {
		const now = Date.now();
		const result = MealSchema.safeParse({
			id: '550e8400-e29b-41d4-a716-446655440000',
			timestamp: now,
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5,
			source: 'manual',
			createdAt: now,
			updatedAt: now
		});
		expect(result.success).toBe(true);
		if (result.success) {
			// Verify timestamp is stored as integer (Unix ms)
			expect(Number.isInteger(result.data.timestamp)).toBe(true);
			// Verify it's a reasonable timestamp (after 2020)
			expect(result.data.timestamp).toBeGreaterThan(1577836800000);
		}
	});

	it('rejects non-integer timestamp', () => {
		const result = MealSchema.safeParse({
			id: '550e8400-e29b-41d4-a716-446655440000',
			timestamp: 1706443200000.5, // Not an integer
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5,
			source: 'manual',
			createdAt: Date.now(),
			updatedAt: Date.now()
		});
		expect(result.success).toBe(false);
	});

	it('rejects negative timestamp', () => {
		const result = MealSchema.safeParse({
			id: '550e8400-e29b-41d4-a716-446655440000',
			timestamp: -1,
			items: [{ name: 'Test', carbs: 10, protein: 5, fat: 5 }],
			totalCarbs: 10,
			totalProtein: 5,
			totalFat: 5,
			source: 'manual',
			createdAt: Date.now(),
			updatedAt: Date.now()
		});
		expect(result.success).toBe(false);
	});
});

describe('MacroDataSchema', () => {
	it('rejects negative values', () => {
		expect(MacroDataSchema.safeParse({ carbs: -1, protein: 0, fat: 0 }).success).toBe(false);
		expect(MacroDataSchema.safeParse({ carbs: 0, protein: -1, fat: 0 }).success).toBe(false);
		expect(MacroDataSchema.safeParse({ carbs: 0, protein: 0, fat: -1 }).success).toBe(false);
	});

	it('accepts zero values', () => {
		const result = MacroDataSchema.safeParse({ carbs: 0, protein: 0, fat: 0 });
		expect(result.success).toBe(true);
	});

	it('accepts decimal values', () => {
		const result = MacroDataSchema.safeParse({ carbs: 10.5, protein: 5.25, fat: 2.75 });
		expect(result.success).toBe(true);
	});
});

describe('Meal creation flow integration', () => {
	it('totals are calculated correctly before validation', () => {
		const items = [
			{ name: 'Apple', carbs: 25, protein: 0, fat: 0 },
			{ name: 'Peanut Butter', carbs: 6, protein: 8, fat: 16 },
			{ name: 'Honey', carbs: 17, protein: 0, fat: 0 }
		];

		// Calculate totals using the utility function
		const totals = sumMacros(items);

		// Verify totals are correct
		expect(totals.carbs).toBe(48);
		expect(totals.protein).toBe(8);
		expect(totals.fat).toBe(16);

		// Create the meal input with calculated totals
		const mealInput = {
			timestamp: Date.now(),
			items,
			totalCarbs: totals.carbs,
			totalProtein: totals.protein,
			totalFat: totals.fat,
			source: 'manual' as const
		};

		// Validate the complete meal
		const result = CreateMealInputSchema.safeParse(mealInput);
		expect(result.success).toBe(true);
	});

	it('timestamp conversion from Date to Unix ms', () => {
		// Use a known UTC date
		const isoString = '2026-02-05T12:30:00.000Z';
		const date = new Date(isoString);
		const unixMs = date.getTime();

		// Verify timestamp is an integer
		expect(Number.isInteger(unixMs)).toBe(true);
		// Verify it's a reasonable future timestamp (after 2025)
		expect(unixMs).toBeGreaterThan(1735689600000); // 2025-01-01

		// Verify we can convert back to the same ISO string
		const reconstructedDate = new Date(unixMs);
		expect(reconstructedDate.toISOString()).toBe(isoString);
	});
});
