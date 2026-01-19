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

/**
 * Check if IndexedDB is available and accessible
 * Returns null if successful, or an error message if not
 */
export async function checkDatabaseAvailability(): Promise<string | null> {
  // Check if IndexedDB API exists
  if (typeof indexedDB === 'undefined') {
    return 'IndexedDB is not supported in this browser';
  }

  try {
    // Attempt to open the database to verify permissions
    await db.open();
    return null;
  } catch (error) {
    // Handle specific Dexie/IndexedDB errors
    if (error instanceof Error) {
      const message = error.message.toLowerCase();

      if (message.includes('permission') || message.includes('denied')) {
        return 'Storage permission denied. This often happens in private browsing mode or when site data is blocked.';
      }

      if (message.includes('quota')) {
        return 'Storage quota exceeded. Please free up some space on your device.';
      }

      if (message.includes('blocked')) {
        return 'Database access was blocked by browser settings.';
      }

      return `Database error: ${error.message}`;
    }

    return 'An unknown storage error occurred';
  }
}
