/**
 * Workstream D: Duplicate Detection Service
 * Branch: dev-4
 *
 * Detects duplicate BSL readings when importing CSV data.
 */

import type { ParsedCSVRow, DuplicateMatch, PhysiologicalEvent } from '$lib/types';
import { getEventService } from '$lib/services';

/**
 * Time window for near-duplicate detection (5 minutes in ms)
 */
const NEAR_DUPLICATE_WINDOW_MS = 5 * 60 * 1000;

/**
 * Find duplicates between import rows and existing events
 *
 * @param rows - Parsed CSV rows to check
 * @returns Array of duplicate matches
 */
export async function findDuplicates(rows: ParsedCSVRow[]): Promise<DuplicateMatch[]> {
  if (rows.length === 0) return [];

  const eventService = getEventService();

  // Get the date range of import rows
  const timestamps = rows.map((r) => r.timestamp.getTime());
  const minTime = Math.min(...timestamps);
  const maxTime = Math.max(...timestamps);

  // Expand range to account for near-duplicates
  const rangeStart = new Date(minTime - NEAR_DUPLICATE_WINDOW_MS);
  const rangeEnd = new Date(maxTime + NEAR_DUPLICATE_WINDOW_MS);

  // Fetch existing BSL events in this range
  const existingEvents = await eventService.getEventsByDateRange(rangeStart, rangeEnd);
  const bslEvents = existingEvents.filter((e) => e.eventType === 'bsl');

  if (bslEvents.length === 0) return [];

  const duplicates: DuplicateMatch[] = [];

  for (const row of rows) {
    const match = findMatchingEvent(row, bslEvents);
    if (match) {
      duplicates.push(match);
    }
  }

  return duplicates;
}

/**
 * Find a matching event for a parsed row
 *
 * @param row - Parsed CSV row
 * @param existingEvents - Existing BSL events to check against
 * @returns DuplicateMatch if found, null otherwise
 */
function findMatchingEvent(
  row: ParsedCSVRow,
  existingEvents: PhysiologicalEvent[]
): DuplicateMatch | null {
  const rowTime = row.timestamp.getTime();

  for (const event of existingEvents) {
    const eventTime = new Date(event.timestamp).getTime();
    const timeDiff = Math.abs(rowTime - eventTime);

    // Check for exact match (same timestamp and value)
    if (timeDiff === 0 && Math.abs(event.value - row.value) < 0.01) {
      return {
        importRow: row,
        existingEvent: event,
        matchType: 'exact',
        timeDifferenceMs: 0
      };
    }

    // Check for near-duplicate (within 5 min window and similar value)
    if (timeDiff <= NEAR_DUPLICATE_WINDOW_MS) {
      // Values should be within 0.5 mmol/L to be considered near-duplicate
      if (Math.abs(event.value - row.value) < 0.5) {
        return {
          importRow: row,
          existingEvent: event,
          matchType: 'near',
          timeDifferenceMs: timeDiff
        };
      }
    }
  }

  return null;
}

/**
 * Filter rows based on duplicate strategy
 *
 * @param rows - All parsed rows
 * @param duplicates - Detected duplicates
 * @param strategy - How to handle duplicates
 * @returns Rows to import after filtering
 */
export function filterRowsByStrategy(
  rows: ParsedCSVRow[],
  duplicates: DuplicateMatch[],
  strategy: 'skip' | 'keep-existing' | 'keep-import' | 'keep-both'
): {
  toImport: ParsedCSVRow[];
  toSkip: ParsedCSVRow[];
  toDelete: PhysiologicalEvent[];
} {
  const duplicateRowSet = new Set(duplicates.map((d) => d.importRow));

  switch (strategy) {
    case 'skip':
    case 'keep-existing':
      // Skip all duplicate import rows
      return {
        toImport: rows.filter((r) => !duplicateRowSet.has(r)),
        toSkip: rows.filter((r) => duplicateRowSet.has(r)),
        toDelete: []
      };

    case 'keep-import':
      // Import all, delete existing duplicates
      return {
        toImport: rows,
        toSkip: [],
        toDelete: duplicates.map((d) => d.existingEvent)
      };

    case 'keep-both':
      // Import all, keep existing
      return {
        toImport: rows,
        toSkip: [],
        toDelete: []
      };

    default:
      return {
        toImport: rows.filter((r) => !duplicateRowSet.has(r)),
        toSkip: rows.filter((r) => duplicateRowSet.has(r)),
        toDelete: []
      };
  }
}

/**
 * Get duplicate statistics for display
 *
 * @param duplicates - Detected duplicates
 * @returns Summary statistics
 */
export function getDuplicateStats(duplicates: DuplicateMatch[]): {
  exact: number;
  near: number;
  total: number;
} {
  const exact = duplicates.filter((d) => d.matchType === 'exact').length;
  const near = duplicates.filter((d) => d.matchType === 'near').length;

  return {
    exact,
    near,
    total: duplicates.length
  };
}
