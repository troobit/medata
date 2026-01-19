import { v4 as uuidv4 } from 'uuid';
import { db } from '$lib/db';
import type { MealPreset, CreatePresetInput, UpdatePresetInput } from '$lib/types';
import type { IPresetRepository } from './IPresetRepository';

/**
 * IndexedDB implementation of the preset repository using Dexie.js
 */
export class IndexedDBPresetRepository implements IPresetRepository {
  async create(input: CreatePresetInput): Promise<MealPreset> {
    const now = new Date();
    const preset: MealPreset = {
      ...input,
      id: uuidv4(),
      createdAt: now,
      updatedAt: now
    };

    await db.presets.add(preset);
    return preset;
  }

  async getById(id: string): Promise<MealPreset | null> {
    const preset = await db.presets.get(id);
    return preset ?? null;
  }

  async update(id: string, updates: UpdatePresetInput): Promise<MealPreset> {
    const existing = await this.getById(id);
    if (!existing) {
      throw new Error(`Preset with id ${id} not found`);
    }

    const updated: MealPreset = {
      ...existing,
      ...updates,
      updatedAt: new Date()
    };

    await db.presets.put(updated);
    return updated;
  }

  async delete(id: string): Promise<void> {
    await db.presets.delete(id);
  }

  async getAll(): Promise<MealPreset[]> {
    return db.presets.orderBy('name').toArray();
  }

  async getByName(name: string): Promise<MealPreset | null> {
    const preset = await db.presets.where('name').equalsIgnoreCase(name).first();
    return preset ?? null;
  }

  async clear(): Promise<void> {
    await db.presets.clear();
  }
}
