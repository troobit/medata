/**
 * Core types for meals and food items.
 * Per design document section 4.1
 */

/**
 * Macronutrient data in grams.
 * Used for both individual food items and meal totals.
 */
export interface MacroData {
	carbs: number;
	protein: number;
	fat: number;
}

/**
 * A food item with name and macronutrients.
 * Per design: quantity and unit are not stored - only name + macros.
 */
export interface FoodItem {
	name: string;
	carbs: number; // grams, non-negative
	protein: number; // grams, non-negative
	fat: number; // grams, non-negative
}

/**
 * A food item as returned by AI recognition.
 * Includes quantity/unit which are used for display but discarded on save (D-DES-014).
 */
export interface RecognisedFoodItem extends FoodItem {
	quantity: number;
	unit: string;
	confidence: number; // 0-1
}

/**
 * Source of meal data.
 * Req 4.2: Record the data source for each meal.
 */
export type MealDataSource = 'manual' | 'ai_image' | 'label_scan' | 'preset';

/**
 * Category for meal presets.
 */
export type PresetCategory = 'meal' | 'snack';

/**
 * A stored meal record.
 * Per design section 4.1.
 */
export interface Meal {
	id: string;
	timestamp: number; // Unix ms, UTC (Req 4.7)
	items: FoodItem[];
	totalCarbs: number; // Stored, immutable once saved (D-DES-012)
	totalProtein: number;
	totalFat: number;
	source: MealDataSource; // Req 4.2
	imageUrl?: string; // May expire after 30 days
	confidence?: number; // From AI, 0-1
	createdAt: number; // Unix ms (Req 10.1)
	updatedAt: number; // Unix ms (Req 10.2)
}

/**
 * Input for creating a new meal.
 * Per design section 3.3.
 */
export interface CreateMealInput {
	timestamp: number; // Unix ms, UTC
	items: FoodItem[];
	totalCarbs: number; // Calculated before save
	totalProtein: number;
	totalFat: number;
	source: MealDataSource;
	imageUrl?: string;
	confidence?: number;
}

/**
 * Input for updating an existing meal.
 */
export interface UpdateMealInput {
	timestamp?: number;
	items?: FoodItem[];
	totalCarbs?: number;
	totalProtein?: number;
	totalFat?: number;
	imageUrl?: string;
}

/**
 * A saved meal preset for quick logging.
 * Req 6.1-6.8.
 */
export interface Preset {
	id: string;
	name: string; // Can be emoji-only (Req 6.1)
	category: PresetCategory;
	items: FoodItem[];
	totalCarbs: number;
	totalProtein: number;
	totalFat: number;
	createdAt: number;
	updatedAt: number;
}

/**
 * Input for creating a new preset.
 */
export interface CreatePresetInput {
	name: string;
	category: PresetCategory;
	items: FoodItem[];
}

/**
 * Input for updating an existing preset.
 */
export interface UpdatePresetInput {
	name?: string;
	category?: PresetCategory;
	items?: FoodItem[];
}
