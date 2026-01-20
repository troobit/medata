import { db, MeDataDB, checkDatabaseAvailability } from './schema';

export { db, MeDataDB, checkDatabaseAvailability };

/**
 * Get the database instance (for dependency injection patterns)
 */
export function getDb(): MeDataDB {
  return db;
}
