import type { MacroData, MealItem } from './events';

/**
 * Preset for saved meals that can be quickly logged
 */
export interface MealPreset {
  id: string;
  name: string;
  items: MealItem[];
  totalMacros: MacroData;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Input type for creating a new preset
 */
export type CreatePresetInput = Omit<MealPreset, 'id' | 'createdAt' | 'updatedAt'>;

/**
 * Input type for updating an existing preset
 */
export type UpdatePresetInput = Partial<Omit<MealPreset, 'id' | 'createdAt'>>;
