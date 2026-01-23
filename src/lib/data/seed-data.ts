/**
 * Minimal Seed Data for UI Development
 *
 * Hardcoded arrays for testing - no dynamic generation, no stochastic variation.
 * Data spans approximately 3 days with 5-minute intervals for blood glucose readings.
 *
 * Scope: UI testing only - regression analysis is explicitly out of scope.
 */

import type { PhysiologicalEvent } from '$lib/types/events';

/**
 * Base timestamp for seed data: 1st January 2025 at 00:00:00 UTC
 */
const BASE_DATE = new Date('2025-01-01T00:00:00.000Z');

/**
 * Helper to create a timestamp offset from base date
 */
function ts(dayOffset: number, hours: number, minutes: number): Date {
  const date = new Date(BASE_DATE);
  date.setUTCDate(date.getUTCDate() + dayOffset);
  date.setUTCHours(hours, minutes, 0, 0);
  return date;
}

/**
 * Helper to create a unique ID from components
 */
function id(type: string, day: number, index: number): string {
  return `seed-${type}-d${day}-${index.toString().padStart(3, '0')}`;
}

// ============================================================================
// BLOOD GLUCOSE READINGS (~50 values, 4-12 mmol/L)
// ============================================================================

/**
 * Hardcoded blood glucose values in mmol/L.
 * Realistic range: 4.0-12.0 mmol/L (normal to elevated).
 * Pattern simulates typical daily variation without randomisation.
 */
export const SEED_BG_VALUES: number[] = [
  // Day 1 - Morning (waking, dawn phenomenon)
  6.2, 6.5, 6.8, 7.1, 7.4, 7.2,
  // Day 1 - Post-breakfast rise
  8.5, 9.2, 10.1, 9.8, 9.0, 8.2,
  // Day 1 - Pre-lunch stable
  7.0, 6.8, 6.5, 6.3,
  // Day 1 - Post-lunch rise
  8.0, 8.8, 9.5, 9.2, 8.5, 7.8,
  // Day 1 - Afternoon
  7.2, 6.9, 6.6, 6.4,
  // Day 1 - Post-dinner rise
  7.5, 8.2, 9.0, 8.6, 8.0, 7.4,
  // Day 1 - Evening/overnight
  6.8, 6.5, 6.2, 5.9, 5.7,
  // Day 2 - Morning
  5.5, 5.8, 6.1, 6.4,
  // Day 2 - Post-breakfast
  7.8, 8.5, 9.0, 8.4, 7.6,
  // Day 2 - Mid-day
  7.0, 6.7, 6.4,
  // Day 3 - Partial day
  5.2, 5.6, 6.0, 6.5
];

/**
 * Timestamps for blood glucose readings.
 * 5-minute intervals spanning approximately 3 days.
 */
export const SEED_BG_TIMESTAMPS: Date[] = [
  // Day 1 - Morning (06:00 - 06:30)
  ts(0, 6, 0), ts(0, 6, 5), ts(0, 6, 10), ts(0, 6, 15), ts(0, 6, 20), ts(0, 6, 25),
  // Day 1 - Post-breakfast (08:00 - 08:55)
  ts(0, 8, 0), ts(0, 8, 10), ts(0, 8, 20), ts(0, 8, 30), ts(0, 8, 40), ts(0, 8, 50),
  // Day 1 - Pre-lunch (11:30 - 12:00)
  ts(0, 11, 30), ts(0, 11, 40), ts(0, 11, 50), ts(0, 12, 0),
  // Day 1 - Post-lunch (13:00 - 14:40)
  ts(0, 13, 0), ts(0, 13, 20), ts(0, 13, 40), ts(0, 14, 0), ts(0, 14, 20), ts(0, 14, 40),
  // Day 1 - Afternoon (16:00 - 16:45)
  ts(0, 16, 0), ts(0, 16, 15), ts(0, 16, 30), ts(0, 16, 45),
  // Day 1 - Post-dinner (19:00 - 20:40)
  ts(0, 19, 0), ts(0, 19, 20), ts(0, 19, 40), ts(0, 20, 0), ts(0, 20, 20), ts(0, 20, 40),
  // Day 1 - Evening/overnight (22:00 - 23:00)
  ts(0, 22, 0), ts(0, 22, 15), ts(0, 22, 30), ts(0, 22, 45), ts(0, 23, 0),
  // Day 2 - Morning (06:00 - 06:45)
  ts(1, 6, 0), ts(1, 6, 15), ts(1, 6, 30), ts(1, 6, 45),
  // Day 2 - Post-breakfast (08:00 - 08:40)
  ts(1, 8, 0), ts(1, 8, 10), ts(1, 8, 20), ts(1, 8, 30), ts(1, 8, 40),
  // Day 2 - Mid-day (12:00 - 12:30)
  ts(1, 12, 0), ts(1, 12, 15), ts(1, 12, 30),
  // Day 3 - Partial (06:00 - 06:45)
  ts(2, 6, 0), ts(2, 6, 15), ts(2, 6, 30), ts(2, 6, 45)
];

// ============================================================================
// INSULIN ENTRIES (basal + bolus)
// ============================================================================

/**
 * Hardcoded insulin entries.
 * Basal: 15 units twice daily (morning and evening)
 * Bolus: varies with meals (4-10 units)
 */
export const SEED_INSULIN_ENTRIES: Array<{
  timestamp: Date;
  value: number;
  type: 'basal' | 'bolus';
}> = [
  // Day 1
  { timestamp: ts(0, 7, 0), value: 15, type: 'basal' },
  { timestamp: ts(0, 7, 30), value: 6, type: 'bolus' },  // Breakfast
  { timestamp: ts(0, 12, 30), value: 8, type: 'bolus' }, // Lunch
  { timestamp: ts(0, 18, 30), value: 10, type: 'bolus' }, // Dinner
  { timestamp: ts(0, 21, 0), value: 15, type: 'basal' },
  // Day 2
  { timestamp: ts(1, 7, 0), value: 15, type: 'basal' },
  { timestamp: ts(1, 7, 30), value: 5, type: 'bolus' },  // Breakfast
  { timestamp: ts(1, 12, 30), value: 7, type: 'bolus' }, // Lunch
  { timestamp: ts(1, 21, 0), value: 15, type: 'basal' },
  // Day 3
  { timestamp: ts(2, 7, 0), value: 15, type: 'basal' }
];

// ============================================================================
// EXERCISE ENTRIES (2-3 activities)
// ============================================================================

/**
 * Hardcoded exercise entries.
 * Mix of intensities and types.
 */
export const SEED_EXERCISE_ENTRIES: Array<{
  timestamp: Date;
  durationMinutes: number;
  intensity: 'low' | 'moderate' | 'high';
  category: string;
  exerciseType: string;
}> = [
  {
    timestamp: ts(0, 17, 0),
    durationMinutes: 30,
    intensity: 'low',
    category: 'walking',
    exerciseType: 'Evening walk'
  },
  {
    timestamp: ts(1, 7, 0),
    durationMinutes: 45,
    intensity: 'moderate',
    category: 'cycling',
    exerciseType: 'Morning cycle'
  },
  {
    timestamp: ts(2, 10, 0),
    durationMinutes: 20,
    intensity: 'high',
    category: 'hiit',
    exerciseType: 'HIIT workout'
  }
];

// ============================================================================
// COMBINED EVENTS (ready for DB seeding)
// ============================================================================

/**
 * Generate all seed events as PhysiologicalEvent objects.
 * Ready for direct insertion into IndexedDB.
 */
export function generateSeedEvents(): PhysiologicalEvent[] {
  const events: PhysiologicalEvent[] = [];
  const now = new Date();

  // Blood glucose readings
  for (let i = 0; i < SEED_BG_VALUES.length; i++) {
    const timestamp = SEED_BG_TIMESTAMPS[i];
    const day = Math.floor((timestamp.getTime() - BASE_DATE.getTime()) / (24 * 60 * 60 * 1000));
    events.push({
      id: id('bsl', day, i),
      timestamp,
      eventType: 'bsl',
      value: SEED_BG_VALUES[i],
      metadata: {
        unit: 'mmol/L',
        source: 'csv-import',
        device: 'Seed Data'
      },
      createdAt: now,
      updatedAt: now,
      synced: false
    });
  }

  // Insulin entries
  SEED_INSULIN_ENTRIES.forEach((entry, i) => {
    const day = Math.floor((entry.timestamp.getTime() - BASE_DATE.getTime()) / (24 * 60 * 60 * 1000));
    events.push({
      id: id('insulin', day, i),
      timestamp: entry.timestamp,
      eventType: 'insulin',
      value: entry.value,
      metadata: {
        type: entry.type
      },
      createdAt: now,
      updatedAt: now,
      synced: false
    });
  });

  // Exercise entries
  SEED_EXERCISE_ENTRIES.forEach((entry, i) => {
    const day = Math.floor((entry.timestamp.getTime() - BASE_DATE.getTime()) / (24 * 60 * 60 * 1000));
    events.push({
      id: id('exercise', day, i),
      timestamp: entry.timestamp,
      eventType: 'exercise',
      value: entry.durationMinutes,
      metadata: {
        intensity: entry.intensity,
        category: entry.category,
        exerciseType: entry.exerciseType,
        durationMinutes: entry.durationMinutes,
        source: 'manual'
      },
      createdAt: now,
      updatedAt: now,
      synced: false
    });
  });

  // Sort by timestamp
  events.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

  return events;
}

/**
 * Count of seed events by type
 */
export const SEED_DATA_COUNTS = {
  bsl: SEED_BG_VALUES.length,
  insulin: SEED_INSULIN_ENTRIES.length,
  exercise: SEED_EXERCISE_ENTRIES.length,
  total: SEED_BG_VALUES.length + SEED_INSULIN_ENTRIES.length + SEED_EXERCISE_ENTRIES.length
} as const;
