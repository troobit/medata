/**
 * Utility functions for macro calculations.
 * Per design section 4.1 and D-DES-012.
 */
import type { MacroData, FoodItem } from '$lib/types/index.js';

/**
 * Calculate total macros from an array of food items.
 * Used before saving meals (D-DES-012).
 *
 * @param items - Array of food items with macro values
 * @returns Total macros (carbs, protein, fat) in grams
 */
export function sumMacros(items: Pick<FoodItem, 'carbs' | 'protein' | 'fat'>[]): MacroData {
	return items.reduce(
		(acc, item) => ({
			carbs: acc.carbs + item.carbs,
			protein: acc.protein + item.protein,
			fat: acc.fat + item.fat
		}),
		{ carbs: 0, protein: 0, fat: 0 }
	);
}
