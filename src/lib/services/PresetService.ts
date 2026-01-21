/**
 * Meal Preset Service
 * Task 25: Meal preset management (save and recall common meals)
 *
 * Provides CRUD operations for meal presets.
 */

import type {
  MealPreset,
  CreatePresetInput,
  UpdatePresetInput,
  MacroData,
  MealItem
} from '$lib/types';
import { db } from '$lib/db/schema';
import { v4 as uuidv4 } from 'uuid';

export class PresetService {
  /**
   * Create a new preset
   */
  async create(input: CreatePresetInput): Promise<MealPreset> {
    const now = new Date();
    const preset: MealPreset = {
      id: uuidv4(),
      name: input.name,
      items: input.items,
      totalMacros: input.totalMacros,
      createdAt: now,
      updatedAt: now
    };

    await db.presets.add(preset);
    return preset;
  }

  /**
   * Get a preset by ID
   */
  async getById(id: string): Promise<MealPreset | null> {
    const preset = await db.presets.get(id);
    return preset || null;
  }

  /**
   * Get all presets, sorted by most recently used
   */
  async getAll(): Promise<MealPreset[]> {
    return db.presets.orderBy('updatedAt').reverse().toArray();
  }

  /**
   * Search presets by name
   */
  async searchByName(query: string): Promise<MealPreset[]> {
    const lowerQuery = query.toLowerCase();
    return db.presets.filter((preset) => preset.name.toLowerCase().includes(lowerQuery)).toArray();
  }

  /**
   * Update a preset
   */
  async update(id: string, updates: UpdatePresetInput): Promise<MealPreset> {
    const existing = await db.presets.get(id);
    if (!existing) {
      throw new Error(`Preset not found: ${id}`);
    }

    const updated: MealPreset = {
      ...existing,
      ...updates,
      updatedAt: new Date()
    };

    await db.presets.put(updated);
    return updated;
  }

  /**
   * Mark preset as recently used (updates the updatedAt timestamp)
   */
  async markUsed(id: string): Promise<void> {
    await db.presets.update(id, { updatedAt: new Date() });
  }

  /**
   * Delete a preset
   */
  async delete(id: string): Promise<void> {
    await db.presets.delete(id);
  }

  /**
   * Get the most recently used presets
   */
  async getRecent(limit: number = 5): Promise<MealPreset[]> {
    return db.presets.orderBy('updatedAt').reverse().limit(limit).toArray();
  }

  /**
   * Create a preset from current meal items
   */
  async createFromItems(name: string, items: MealItem[]): Promise<MealPreset> {
    const totalMacros = this.calculateTotalMacros(items);
    return this.create({ name, items, totalMacros });
  }

  /**
   * Calculate total macros from meal items
   */
  calculateTotalMacros(items: MealItem[]): MacroData {
    return items.reduce(
      (total, item) => ({
        calories: total.calories + (item.macros?.calories || 0),
        carbs: total.carbs + (item.macros?.carbs || 0),
        protein: total.protein + (item.macros?.protein || 0),
        fat: total.fat + (item.macros?.fat || 0)
      }),
      { calories: 0, carbs: 0, protein: 0, fat: 0 }
    );
  }

  /**
   * Export all presets
   */
  async exportAll(): Promise<MealPreset[]> {
    return db.presets.toArray();
  }

  /**
   * Import presets (with duplicate detection by name)
   */
  async importPresets(
    presets: MealPreset[],
    strategy: 'skip' | 'replace' | 'merge' = 'skip'
  ): Promise<{ imported: number; skipped: number }> {
    let imported = 0;
    let skipped = 0;

    for (const preset of presets) {
      const existing = await db.presets.where('name').equals(preset.name).first();

      if (existing) {
        if (strategy === 'skip') {
          skipped++;
          continue;
        } else if (strategy === 'replace') {
          await db.presets.delete(existing.id);
        } else if (strategy === 'merge') {
          // Merge items from both presets
          const mergedItems = [...existing.items, ...preset.items];
          const mergedMacros = this.calculateTotalMacros(mergedItems);
          await db.presets.update(existing.id, {
            items: mergedItems,
            totalMacros: mergedMacros,
            updatedAt: new Date()
          });
          imported++;
          continue;
        }
      }

      await db.presets.add({
        ...preset,
        id: uuidv4(),
        createdAt: new Date(),
        updatedAt: new Date()
      });
      imported++;
    }

    return { imported, skipped };
  }

  /**
   * Clear all presets
   */
  async clearAll(): Promise<void> {
    await db.presets.clear();
  }
}

// Singleton instance
let presetServiceInstance: PresetService | null = null;

export function getPresetService(): PresetService {
  if (!presetServiceInstance) {
    presetServiceInstance = new PresetService();
  }
  return presetServiceInstance;
}
