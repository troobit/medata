import Dexie, { type EntityTable } from 'dexie';
import type { PhysiologicalEvent, MealPreset } from '$lib/types';

/**
 * Database schema for MeData
 * Uses Dexie.js for IndexedDB wrapper with TypeScript support
 */
export class MeDataDB extends Dexie {
  events!: EntityTable<PhysiologicalEvent, 'id'>;
  presets!: EntityTable<MealPreset, 'id'>;

  constructor() {
    super('medata');

    this.version(1).stores({
      // Primary key is 'id', indexed by timestamp, eventType, and compound index
      events: 'id, timestamp, eventType, [eventType+timestamp], createdAt',
      // Primary key is 'id', indexed by name and createdAt
      presets: 'id, name, createdAt'
    });
  }
}

/**
 * Singleton database instance
 */
export const db = new MeDataDB();
