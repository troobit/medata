/**
 * Workstream C: Food Density Database
 * A curated subset of USDA FNDDS data for local volume estimation.
 *
 * Density values are in g/mL (grams per milliliter)
 * Macros are per gram of food
 *
 * Sources:
 * - USDA FNDDS (Food and Nutrient Database for Dietary Studies)
 * - GoCARB research data
 */

import type { FoodDensityEntry } from '$lib/types/local-estimation';

/**
 * Common food density entries with macro data per gram.
 * Categories: grains, proteins, vegetables, fruits, dairy, mixed, snacks
 */
export const FOOD_DENSITY_DATABASE: FoodDensityEntry[] = [
  // === GRAINS & STARCHES ===
  {
    id: 'rice-white-cooked',
    name: 'White Rice (cooked)',
    category: 'grains',
    densityGPerMl: 1.1,
    macrosPerGram: { calories: 1.3, carbs: 0.28, protein: 0.027, fat: 0.003 }
  },
  {
    id: 'rice-brown-cooked',
    name: 'Brown Rice (cooked)',
    category: 'grains',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 1.11, carbs: 0.23, protein: 0.026, fat: 0.009 }
  },
  {
    id: 'pasta-cooked',
    name: 'Pasta (cooked)',
    category: 'grains',
    densityGPerMl: 1.15,
    macrosPerGram: { calories: 1.31, carbs: 0.25, protein: 0.05, fat: 0.011 }
  },
  {
    id: 'bread-white',
    name: 'White Bread',
    category: 'grains',
    densityGPerMl: 0.35,
    macrosPerGram: { calories: 2.65, carbs: 0.49, protein: 0.09, fat: 0.033 }
  },
  {
    id: 'bread-whole-wheat',
    name: 'Whole Wheat Bread',
    category: 'grains',
    densityGPerMl: 0.38,
    macrosPerGram: { calories: 2.47, carbs: 0.41, protein: 0.13, fat: 0.041 }
  },
  {
    id: 'oatmeal-cooked',
    name: 'Oatmeal (cooked)',
    category: 'grains',
    densityGPerMl: 1.0,
    macrosPerGram: { calories: 0.68, carbs: 0.12, protein: 0.025, fat: 0.014 }
  },
  {
    id: 'potato-mashed',
    name: 'Mashed Potato',
    category: 'grains',
    densityGPerMl: 1.1,
    macrosPerGram: { calories: 0.83, carbs: 0.15, protein: 0.019, fat: 0.021 }
  },
  {
    id: 'potato-roasted',
    name: 'Roasted Potato',
    category: 'grains',
    densityGPerMl: 0.9,
    macrosPerGram: { calories: 1.01, carbs: 0.21, protein: 0.023, fat: 0.01 }
  },
  {
    id: 'chips-hot',
    name: 'Hot Chips / Fries',
    category: 'grains',
    densityGPerMl: 0.55,
    macrosPerGram: { calories: 3.12, carbs: 0.41, protein: 0.034, fat: 0.15 }
  },
  {
    id: 'noodles-cooked',
    name: 'Noodles (cooked)',
    category: 'grains',
    densityGPerMl: 1.1,
    macrosPerGram: { calories: 1.38, carbs: 0.25, protein: 0.047, fat: 0.021 }
  },

  // === PROTEINS ===
  {
    id: 'chicken-breast',
    name: 'Chicken Breast (cooked)',
    category: 'proteins',
    densityGPerMl: 1.1,
    macrosPerGram: { calories: 1.65, carbs: 0, protein: 0.31, fat: 0.036 }
  },
  {
    id: 'chicken-thigh',
    name: 'Chicken Thigh (cooked)',
    category: 'proteins',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 2.09, carbs: 0, protein: 0.26, fat: 0.109 }
  },
  {
    id: 'beef-steak',
    name: 'Beef Steak (cooked)',
    category: 'proteins',
    densityGPerMl: 1.15,
    macrosPerGram: { calories: 2.71, carbs: 0, protein: 0.26, fat: 0.18 }
  },
  {
    id: 'beef-mince',
    name: 'Beef Mince (cooked)',
    category: 'proteins',
    densityGPerMl: 1.0,
    macrosPerGram: { calories: 2.5, carbs: 0, protein: 0.26, fat: 0.15 }
  },
  {
    id: 'pork-chop',
    name: 'Pork Chop (cooked)',
    category: 'proteins',
    densityGPerMl: 1.1,
    macrosPerGram: { calories: 2.31, carbs: 0, protein: 0.27, fat: 0.133 }
  },
  {
    id: 'fish-white',
    name: 'White Fish (cooked)',
    category: 'proteins',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 1.05, carbs: 0, protein: 0.22, fat: 0.012 }
  },
  {
    id: 'fish-salmon',
    name: 'Salmon (cooked)',
    category: 'proteins',
    densityGPerMl: 1.08,
    macrosPerGram: { calories: 2.08, carbs: 0, protein: 0.2, fat: 0.133 }
  },
  {
    id: 'egg-whole',
    name: 'Egg (whole, cooked)',
    category: 'proteins',
    densityGPerMl: 1.03,
    macrosPerGram: { calories: 1.55, carbs: 0.011, protein: 0.126, fat: 0.109 }
  },
  {
    id: 'tofu',
    name: 'Tofu',
    category: 'proteins',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 0.76, carbs: 0.019, protein: 0.08, fat: 0.048 }
  },
  {
    id: 'beans-kidney',
    name: 'Kidney Beans (cooked)',
    category: 'proteins',
    densityGPerMl: 1.08,
    macrosPerGram: { calories: 1.27, carbs: 0.225, protein: 0.087, fat: 0.005 }
  },
  {
    id: 'lentils-cooked',
    name: 'Lentils (cooked)',
    category: 'proteins',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 1.16, carbs: 0.2, protein: 0.09, fat: 0.004 }
  },

  // === VEGETABLES ===
  {
    id: 'broccoli',
    name: 'Broccoli',
    category: 'vegetables',
    densityGPerMl: 0.4,
    macrosPerGram: { calories: 0.34, carbs: 0.07, protein: 0.028, fat: 0.004 }
  },
  {
    id: 'carrots-cooked',
    name: 'Carrots (cooked)',
    category: 'vegetables',
    densityGPerMl: 0.9,
    macrosPerGram: { calories: 0.35, carbs: 0.082, protein: 0.008, fat: 0.002 }
  },
  {
    id: 'peas',
    name: 'Green Peas',
    category: 'vegetables',
    densityGPerMl: 0.75,
    macrosPerGram: { calories: 0.81, carbs: 0.143, protein: 0.054, fat: 0.004 }
  },
  {
    id: 'corn',
    name: 'Corn Kernels',
    category: 'vegetables',
    densityGPerMl: 0.72,
    macrosPerGram: { calories: 0.96, carbs: 0.21, protein: 0.032, fat: 0.014 }
  },
  {
    id: 'spinach-cooked',
    name: 'Spinach (cooked)',
    category: 'vegetables',
    densityGPerMl: 0.85,
    macrosPerGram: { calories: 0.23, carbs: 0.036, protein: 0.029, fat: 0.003 }
  },
  {
    id: 'lettuce',
    name: 'Lettuce',
    category: 'vegetables',
    densityGPerMl: 0.1,
    macrosPerGram: { calories: 0.15, carbs: 0.029, protein: 0.013, fat: 0.002 }
  },
  {
    id: 'tomato',
    name: 'Tomato',
    category: 'vegetables',
    densityGPerMl: 0.95,
    macrosPerGram: { calories: 0.18, carbs: 0.039, protein: 0.009, fat: 0.002 }
  },
  {
    id: 'capsicum',
    name: 'Capsicum / Bell Pepper',
    category: 'vegetables',
    densityGPerMl: 0.5,
    macrosPerGram: { calories: 0.26, carbs: 0.06, protein: 0.01, fat: 0.002 }
  },
  {
    id: 'mushrooms',
    name: 'Mushrooms',
    category: 'vegetables',
    densityGPerMl: 0.45,
    macrosPerGram: { calories: 0.22, carbs: 0.033, protein: 0.031, fat: 0.003 }
  },
  {
    id: 'onion-cooked',
    name: 'Onion (cooked)',
    category: 'vegetables',
    densityGPerMl: 0.85,
    macrosPerGram: { calories: 0.44, carbs: 0.104, protein: 0.013, fat: 0.002 }
  },
  {
    id: 'zucchini',
    name: 'Zucchini',
    category: 'vegetables',
    densityGPerMl: 0.6,
    macrosPerGram: { calories: 0.17, carbs: 0.031, protein: 0.012, fat: 0.003 }
  },

  // === FRUITS ===
  {
    id: 'apple-diced',
    name: 'Apple (diced)',
    category: 'fruits',
    densityGPerMl: 0.65,
    macrosPerGram: { calories: 0.52, carbs: 0.138, protein: 0.003, fat: 0.002 }
  },
  {
    id: 'banana-sliced',
    name: 'Banana (sliced)',
    category: 'fruits',
    densityGPerMl: 0.95,
    macrosPerGram: { calories: 0.89, carbs: 0.228, protein: 0.011, fat: 0.003 }
  },
  {
    id: 'berries-mixed',
    name: 'Mixed Berries',
    category: 'fruits',
    densityGPerMl: 0.6,
    macrosPerGram: { calories: 0.43, carbs: 0.097, protein: 0.01, fat: 0.003 }
  },
  {
    id: 'grapes',
    name: 'Grapes',
    category: 'fruits',
    densityGPerMl: 0.65,
    macrosPerGram: { calories: 0.69, carbs: 0.181, protein: 0.007, fat: 0.002 }
  },
  {
    id: 'orange-segments',
    name: 'Orange (segments)',
    category: 'fruits',
    densityGPerMl: 0.85,
    macrosPerGram: { calories: 0.47, carbs: 0.118, protein: 0.009, fat: 0.001 }
  },
  {
    id: 'mango-diced',
    name: 'Mango (diced)',
    category: 'fruits',
    densityGPerMl: 0.8,
    macrosPerGram: { calories: 0.6, carbs: 0.15, protein: 0.008, fat: 0.004 }
  },
  {
    id: 'watermelon',
    name: 'Watermelon',
    category: 'fruits',
    densityGPerMl: 0.6,
    macrosPerGram: { calories: 0.3, carbs: 0.076, protein: 0.006, fat: 0.002 }
  },
  {
    id: 'pineapple',
    name: 'Pineapple',
    category: 'fruits',
    densityGPerMl: 0.75,
    macrosPerGram: { calories: 0.5, carbs: 0.131, protein: 0.005, fat: 0.001 }
  },

  // === DAIRY ===
  {
    id: 'milk',
    name: 'Milk (whole)',
    category: 'dairy',
    densityGPerMl: 1.03,
    macrosPerGram: { calories: 0.61, carbs: 0.049, protein: 0.032, fat: 0.033 }
  },
  {
    id: 'yogurt-plain',
    name: 'Yogurt (plain)',
    category: 'dairy',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 0.61, carbs: 0.047, protein: 0.035, fat: 0.033 }
  },
  {
    id: 'yogurt-greek',
    name: 'Greek Yogurt',
    category: 'dairy',
    densityGPerMl: 1.08,
    macrosPerGram: { calories: 0.97, carbs: 0.036, protein: 0.09, fat: 0.05 }
  },
  {
    id: 'cheese-cheddar',
    name: 'Cheddar Cheese',
    category: 'dairy',
    densityGPerMl: 1.1,
    macrosPerGram: { calories: 4.03, carbs: 0.013, protein: 0.249, fat: 0.331 }
  },
  {
    id: 'cheese-mozzarella',
    name: 'Mozzarella',
    category: 'dairy',
    densityGPerMl: 1.0,
    macrosPerGram: { calories: 3.0, carbs: 0.022, protein: 0.22, fat: 0.224 }
  },
  {
    id: 'cream',
    name: 'Cream (heavy)',
    category: 'dairy',
    densityGPerMl: 0.98,
    macrosPerGram: { calories: 3.4, carbs: 0.028, protein: 0.021, fat: 0.365 }
  },
  {
    id: 'ice-cream',
    name: 'Ice Cream',
    category: 'dairy',
    densityGPerMl: 0.55,
    macrosPerGram: { calories: 2.07, carbs: 0.239, protein: 0.035, fat: 0.11 }
  },

  // === MIXED / PREPARED FOODS ===
  {
    id: 'pizza-slice',
    name: 'Pizza',
    category: 'mixed',
    densityGPerMl: 0.6,
    macrosPerGram: { calories: 2.66, carbs: 0.33, protein: 0.11, fat: 0.103 }
  },
  {
    id: 'burger-patty',
    name: 'Burger (with bun)',
    category: 'mixed',
    densityGPerMl: 0.75,
    macrosPerGram: { calories: 2.95, carbs: 0.24, protein: 0.17, fat: 0.14 }
  },
  {
    id: 'sandwich',
    name: 'Sandwich (typical)',
    category: 'mixed',
    densityGPerMl: 0.5,
    macrosPerGram: { calories: 2.32, carbs: 0.29, protein: 0.13, fat: 0.08 }
  },
  {
    id: 'stir-fry',
    name: 'Stir Fry (mixed)',
    category: 'mixed',
    densityGPerMl: 0.85,
    macrosPerGram: { calories: 1.2, carbs: 0.08, protein: 0.1, fat: 0.06 }
  },
  {
    id: 'curry',
    name: 'Curry (with sauce)',
    category: 'mixed',
    densityGPerMl: 1.0,
    macrosPerGram: { calories: 1.5, carbs: 0.08, protein: 0.12, fat: 0.09 }
  },
  {
    id: 'soup-thick',
    name: 'Soup (thick/creamy)',
    category: 'mixed',
    densityGPerMl: 1.02,
    macrosPerGram: { calories: 0.75, carbs: 0.08, protein: 0.03, fat: 0.035 }
  },
  {
    id: 'soup-broth',
    name: 'Soup (broth based)',
    category: 'mixed',
    densityGPerMl: 1.0,
    macrosPerGram: { calories: 0.35, carbs: 0.05, protein: 0.02, fat: 0.01 }
  },
  {
    id: 'salad-mixed',
    name: 'Mixed Salad',
    category: 'mixed',
    densityGPerMl: 0.3,
    macrosPerGram: { calories: 0.2, carbs: 0.035, protein: 0.012, fat: 0.003 }
  },
  {
    id: 'fried-rice',
    name: 'Fried Rice',
    category: 'mixed',
    densityGPerMl: 1.0,
    macrosPerGram: { calories: 1.63, carbs: 0.24, protein: 0.043, fat: 0.059 }
  },
  {
    id: 'sushi-roll',
    name: 'Sushi Roll',
    category: 'mixed',
    densityGPerMl: 0.9,
    macrosPerGram: { calories: 1.5, carbs: 0.27, protein: 0.06, fat: 0.025 }
  },

  // === SNACKS ===
  {
    id: 'chips-packet',
    name: 'Potato Chips (packet)',
    category: 'snacks',
    densityGPerMl: 0.12,
    macrosPerGram: { calories: 5.36, carbs: 0.53, protein: 0.065, fat: 0.345 }
  },
  {
    id: 'popcorn',
    name: 'Popcorn',
    category: 'snacks',
    densityGPerMl: 0.03,
    macrosPerGram: { calories: 3.87, carbs: 0.78, protein: 0.125, fat: 0.044 }
  },
  {
    id: 'nuts-mixed',
    name: 'Mixed Nuts',
    category: 'snacks',
    densityGPerMl: 0.55,
    macrosPerGram: { calories: 6.07, carbs: 0.21, protein: 0.2, fat: 0.54 }
  },
  {
    id: 'chocolate',
    name: 'Chocolate',
    category: 'snacks',
    densityGPerMl: 1.3,
    macrosPerGram: { calories: 5.46, carbs: 0.598, protein: 0.049, fat: 0.31 }
  },
  {
    id: 'cookie',
    name: 'Cookie',
    category: 'snacks',
    densityGPerMl: 0.5,
    macrosPerGram: { calories: 4.88, carbs: 0.64, protein: 0.052, fat: 0.236 }
  },
  {
    id: 'cake',
    name: 'Cake (typical)',
    category: 'snacks',
    densityGPerMl: 0.4,
    macrosPerGram: { calories: 3.57, carbs: 0.51, protein: 0.043, fat: 0.156 }
  },
  {
    id: 'crackers',
    name: 'Crackers',
    category: 'snacks',
    densityGPerMl: 0.15,
    macrosPerGram: { calories: 4.84, carbs: 0.65, protein: 0.095, fat: 0.21 }
  },

  // === SAUCES & CONDIMENTS ===
  {
    id: 'sauce-tomato',
    name: 'Tomato Sauce',
    category: 'sauces',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 0.82, carbs: 0.178, protein: 0.016, fat: 0.004 }
  },
  {
    id: 'sauce-cream',
    name: 'Cream Sauce',
    category: 'sauces',
    densityGPerMl: 1.0,
    macrosPerGram: { calories: 1.5, carbs: 0.06, protein: 0.025, fat: 0.13 }
  },
  {
    id: 'gravy',
    name: 'Gravy',
    category: 'sauces',
    densityGPerMl: 1.05,
    macrosPerGram: { calories: 0.47, carbs: 0.068, protein: 0.019, fat: 0.015 }
  },
  {
    id: 'hummus',
    name: 'Hummus',
    category: 'sauces',
    densityGPerMl: 1.1,
    macrosPerGram: { calories: 1.66, carbs: 0.144, protein: 0.078, fat: 0.096 }
  },
  {
    id: 'mayonnaise',
    name: 'Mayonnaise',
    category: 'sauces',
    densityGPerMl: 0.95,
    macrosPerGram: { calories: 6.8, carbs: 0.006, protein: 0.01, fat: 0.75 }
  }
];

/**
 * Get all unique categories
 */
export function getCategories(): string[] {
  return [...new Set(FOOD_DENSITY_DATABASE.map((f) => f.category))];
}

/**
 * Get foods by category
 */
export function getFoodsByCategory(category: string): FoodDensityEntry[] {
  return FOOD_DENSITY_DATABASE.filter((f) => f.category === category);
}
