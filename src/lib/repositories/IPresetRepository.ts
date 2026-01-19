import type { MealPreset, CreatePresetInput, UpdatePresetInput } from '$lib/types';

/**
 * Repository interface for meal presets
 */
export interface IPresetRepository {
  // CRUD operations
  create(preset: CreatePresetInput): Promise<MealPreset>;
  getById(id: string): Promise<MealPreset | null>;
  update(id: string, updates: UpdatePresetInput): Promise<MealPreset>;
  delete(id: string): Promise<void>;

  // Query operations
  getAll(): Promise<MealPreset[]>;
  getByName(name: string): Promise<MealPreset | null>;

  // Bulk operations
  clear(): Promise<void>;
}
