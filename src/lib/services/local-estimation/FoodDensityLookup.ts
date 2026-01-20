/**
 * Workstream C: Food Density Lookup Service
 * Provides search and lookup functionality for the food density database.
 */

import type { FoodDensityEntry } from '$lib/types/local-estimation';
import {
  FOOD_DENSITY_DATABASE,
  getCategories,
  getFoodsByCategory
} from '$lib/data/food-density';

/**
 * Search result with relevance scoring
 */
export interface SearchResult extends FoodDensityEntry {
  score: number;
}

/**
 * FoodDensityLookup provides search functionality over the USDA food database subset.
 * All operations are synchronous and run entirely in the browser.
 */
export class FoodDensityLookup {
  private database: FoodDensityEntry[];

  constructor() {
    this.database = FOOD_DENSITY_DATABASE;
  }

  /**
   * Search foods by query string.
   * Matches against name and category with fuzzy scoring.
   */
  search(query: string, limit: number = 10): SearchResult[] {
    if (!query || query.trim().length === 0) {
      return [];
    }

    const normalizedQuery = query.toLowerCase().trim();
    const queryTerms = normalizedQuery.split(/\s+/);

    const results: SearchResult[] = this.database
      .map((food) => {
        const score = this.calculateScore(food, queryTerms, normalizedQuery);
        return { ...food, score };
      })
      .filter((result) => result.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, limit);

    return results;
  }

  /**
   * Calculate relevance score for a food entry
   */
  private calculateScore(
    food: FoodDensityEntry,
    queryTerms: string[],
    fullQuery: string
  ): number {
    const name = food.name.toLowerCase();
    const category = food.category.toLowerCase();
    let score = 0;

    // Exact match on name
    if (name === fullQuery) {
      score += 100;
    }
    // Name starts with query
    else if (name.startsWith(fullQuery)) {
      score += 50;
    }
    // Name contains query
    else if (name.includes(fullQuery)) {
      score += 25;
    }

    // Term matching
    for (const term of queryTerms) {
      if (term.length < 2) continue;

      if (name.includes(term)) {
        score += 10;
        // Bonus for word boundary match
        const wordBoundaryRegex = new RegExp(`\\b${term}`, 'i');
        if (wordBoundaryRegex.test(name)) {
          score += 5;
        }
      }

      if (category.includes(term)) {
        score += 5;
      }
    }

    return score;
  }

  /**
   * Get a food by its ID
   */
  getById(id: string): FoodDensityEntry | undefined {
    return this.database.find((f) => f.id === id);
  }

  /**
   * Get all available categories
   */
  getCategories(): string[] {
    return getCategories();
  }

  /**
   * Get all foods in a category
   */
  getByCategory(category: string): FoodDensityEntry[] {
    return getFoodsByCategory(category);
  }

  /**
   * Get all foods (for browsing)
   */
  getAll(): FoodDensityEntry[] {
    return [...this.database];
  }

  /**
   * Get popular/common foods (first of each category)
   */
  getPopular(count: number = 12): FoodDensityEntry[] {
    const categories = this.getCategories();
    const popular: FoodDensityEntry[] = [];

    // Get first item from each category
    for (const category of categories) {
      const items = this.getByCategory(category);
      if (items.length > 0 && popular.length < count) {
        popular.push(items[0]);
      }
    }

    // Fill remaining with more items if needed
    if (popular.length < count) {
      for (const food of this.database) {
        if (!popular.includes(food) && popular.length < count) {
          popular.push(food);
        }
      }
    }

    return popular;
  }

  /**
   * Calculate macros for a given weight of food
   */
  calculateMacros(
    food: FoodDensityEntry,
    weightGrams: number
  ): { calories: number; carbs: number; protein: number; fat: number } {
    return {
      calories: Math.round(food.macrosPerGram.calories * weightGrams),
      carbs: Math.round(food.macrosPerGram.carbs * weightGrams * 10) / 10,
      protein: Math.round(food.macrosPerGram.protein * weightGrams * 10) / 10,
      fat: Math.round(food.macrosPerGram.fat * weightGrams * 10) / 10
    };
  }

  /**
   * Calculate weight from volume using food density
   */
  volumeToWeight(food: FoodDensityEntry, volumeMl: number): number {
    return volumeMl * food.densityGPerMl;
  }

  /**
   * Full pipeline: volume -> weight -> macros
   */
  estimateMacrosFromVolume(
    food: FoodDensityEntry,
    volumeMl: number
  ): {
    weightGrams: number;
    calories: number;
    carbs: number;
    protein: number;
    fat: number;
  } {
    const weightGrams = this.volumeToWeight(food, volumeMl);
    const macros = this.calculateMacros(food, weightGrams);
    return {
      weightGrams: Math.round(weightGrams),
      ...macros
    };
  }
}

// Singleton instance for convenience
export const foodDensityLookup = new FoodDensityLookup();
