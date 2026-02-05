/**
 * Zod validation schemas for meals and food items.
 * Req 3.4: Validate non-negative numbers
 * Req 10.3, 10.5: Raw grams, no artificial ranges
 */
import { z } from 'zod/v4';

/**
 * Schema for macronutrient data.
 * All values must be non-negative numbers (grams).
 */
export const MacroDataSchema = z.object({
	carbs: z.number().nonnegative(),
	protein: z.number().nonnegative(),
	fat: z.number().nonnegative()
});

/**
 * Schema for a food item.
 * Req 3.4: Validate non-negative numbers
 * Req 10.4: Store food names as user-provided strings
 */
export const FoodItemSchema = z.object({
	name: z.string().min(1),
	carbs: z.number().nonnegative(),
	protein: z.number().nonnegative(),
	fat: z.number().nonnegative()
});

/**
 * Schema for AI-recognised food item.
 * Includes quantity/unit which are discarded on save (D-DES-014).
 */
export const RecognisedFoodItemSchema = FoodItemSchema.extend({
	quantity: z.number().positive(),
	unit: z.string().min(1),
	confidence: z.number().min(0).max(1)
});

/**
 * Schema for meal data source.
 */
export const MealDataSourceSchema = z.enum(['manual', 'ai_image', 'label_scan', 'preset']);

/**
 * Schema for preset category.
 */
export const PresetCategorySchema = z.enum(['meal', 'snack']);

/**
 * Schema for creating a new meal.
 * Per design section 4.4.
 */
export const CreateMealInputSchema = z.object({
	timestamp: z.number().int().positive(),
	items: z.array(FoodItemSchema).min(1),
	totalCarbs: z.number().nonnegative(),
	totalProtein: z.number().nonnegative(),
	totalFat: z.number().nonnegative(),
	source: MealDataSourceSchema,
	imageUrl: z.url().optional(),
	confidence: z.number().min(0).max(1).optional()
});

/**
 * Schema for updating an existing meal.
 */
export const UpdateMealInputSchema = z.object({
	timestamp: z.number().int().positive().optional(),
	items: z.array(FoodItemSchema).min(1).optional(),
	totalCarbs: z.number().nonnegative().optional(),
	totalProtein: z.number().nonnegative().optional(),
	totalFat: z.number().nonnegative().optional(),
	imageUrl: z.url().optional()
});

/**
 * Schema for a stored meal.
 */
export const MealSchema = z.object({
	id: z.string().uuid(),
	timestamp: z.number().int().positive(),
	items: z.array(FoodItemSchema).min(1),
	totalCarbs: z.number().nonnegative(),
	totalProtein: z.number().nonnegative(),
	totalFat: z.number().nonnegative(),
	source: MealDataSourceSchema,
	imageUrl: z.url().optional(),
	confidence: z.number().min(0).max(1).optional(),
	createdAt: z.number().int().positive(),
	updatedAt: z.number().int().positive()
});

/**
 * Schema for creating a new preset.
 */
export const CreatePresetInputSchema = z.object({
	name: z.string().min(1),
	category: PresetCategorySchema,
	items: z.array(FoodItemSchema).min(1)
});

/**
 * Schema for updating an existing preset.
 */
export const UpdatePresetInputSchema = z.object({
	name: z.string().min(1).optional(),
	category: PresetCategorySchema.optional(),
	items: z.array(FoodItemSchema).min(1).optional()
});

/**
 * Schema for a stored preset.
 */
export const PresetSchema = z.object({
	id: z.string().uuid(),
	name: z.string().min(1),
	category: PresetCategorySchema,
	items: z.array(FoodItemSchema).min(1),
	totalCarbs: z.number().nonnegative(),
	totalProtein: z.number().nonnegative(),
	totalFat: z.number().nonnegative(),
	createdAt: z.number().int().positive(),
	updatedAt: z.number().int().positive()
});

// Type inference from schemas
export type MacroDataInput = z.infer<typeof MacroDataSchema>;
export type FoodItemInput = z.infer<typeof FoodItemSchema>;
export type RecognisedFoodItemInput = z.infer<typeof RecognisedFoodItemSchema>;
export type CreateMealInputData = z.infer<typeof CreateMealInputSchema>;
export type UpdateMealInputData = z.infer<typeof UpdateMealInputSchema>;
export type MealData = z.infer<typeof MealSchema>;
export type CreatePresetInputData = z.infer<typeof CreatePresetInputSchema>;
export type UpdatePresetInputData = z.infer<typeof UpdatePresetInputSchema>;
export type PresetData = z.infer<typeof PresetSchema>;
