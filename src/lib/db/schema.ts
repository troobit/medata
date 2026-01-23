import Dexie, { type EntityTable } from 'dexie';
import type {
  PhysiologicalEvent,
  MealPreset,
  TestDatasetEntry,
  ValidationResult,
  CorrectionHistoryEntry
} from '$lib/types';

/**
 * Database schema for MeData
 * Uses Dexie.js for IndexedDB wrapper with TypeScript support
 */
export class MeDataDB extends Dexie {
  events!: EntityTable<PhysiologicalEvent, 'id'>;
  presets!: EntityTable<MealPreset, 'id'>;
  testDataset!: EntityTable<TestDatasetEntry, 'id'>;
  validationResults!: EntityTable<ValidationResult, 'testEntryId'>;
  correctionHistory!: EntityTable<CorrectionHistoryEntry, 'id'>;

  constructor() {
    super('medata');

    this.version(1).stores({
      // Primary key is 'id', indexed by timestamp, eventType, and compound index
      events: 'id, timestamp, eventType, [eventType+timestamp], createdAt',
      // Primary key is 'id', indexed by name and createdAt
      presets: 'id, name, createdAt'
    });

    // Version 2: Add validation tables
    this.version(2).stores({
      events: 'id, timestamp, eventType, [eventType+timestamp], createdAt',
      presets: 'id, name, createdAt',
      // Test dataset entries with known ground truth
      testDataset: 'id, category, source, createdAt',
      // Validation results from running AI against test data
      validationResults: 'testEntryId, aiProvider, timestamp, [aiProvider+timestamp]',
      // Correction history from user edits
      correctionHistory: 'id, eventId, aiProvider, category, timestamp, [aiProvider+timestamp]'
    });
  }
}

/**
 * Lazy-initialised singleton database instance
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

/**
 * Check if IndexedDB is available and working
 * Returns null if available, or an error message if not
 */
export async function checkDatabaseAvailability(): Promise<string | null> {
  if (typeof window === 'undefined') {
    return 'Database is only available in the browser';
  }

  if (!('indexedDB' in window)) {
    return 'IndexedDB is not supported in this browser';
  }

  try {
    const testDb = getDb();
    await testDb.events.count();
    return null;
  } catch (error) {
    if (error instanceof Error) {
      // Check for common IndexedDB errors
      if (error.name === 'QuotaExceededError' || error.message.includes('quota')) {
        return 'Storage quota exceeded. Please free up some space.';
      }
      if (error.message.includes('private browsing') || error.message.includes('Private mode')) {
        return 'Private/Incognito browsing mode detected. Please use a regular browser window.';
      }
      return `Database error: ${error.message}`;
    }
    return 'Failed to initialise database';
  }
}
