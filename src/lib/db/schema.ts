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
 * Lazy-initialized singleton database instance
 * Prevents SSR issues by only creating the database in the browser
 */
let _db: MeDataDB | null = null;

export function getDb(): MeDataDB {
  if (!_db) {
    if (typeof window === 'undefined') {
      throw new Error('Database can only be accessed in the browser');
    }
    _db = new MeDataDB();
  }
  return _db;
}

/**
 * @deprecated Use getDb() instead to avoid SSR issues
 */
export const db = typeof window !== 'undefined' ? new MeDataDB() : (null as unknown as MeDataDB);
