/**
 * Test Data Generator for MeData
 *
 * Generates realistic blood glucose data for T1D patients over a 1-month period.
 * Data is stochastic and varies on each run.
 *
 * Usage: npx tsx scripts/generate-test-data.ts
 * Output: static/test-data.json
 */

import { randomUUID } from 'crypto';
import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Types matching the app's data model
interface PhysiologicalEvent {
  id: string;
  timestamp: string;
  eventType: 'bsl' | 'meal' | 'insulin' | 'exercise';
  value: number;
  metadata: Record<string, unknown>;
  createdAt: string;
  updatedAt: string;
  synced?: boolean;
}

interface TestDataOutput {
  version: string;
  type: string;
  createdAt: string;
  count: number;
  events: PhysiologicalEvent[];
}

// Blood glucose parameters for T1D patients (mmol/L)
const BG_PARAMS = {
  // Target ranges
  minNormal: 4.0,
  maxNormal: 8.0,
  // Physiological limits
  minPhysio: 2.5,
  maxPhysio: 20.0,
  // Baseline and variation
  baselineFasting: 6.5,
  baselineVariation: 1.5,
  // Meal effects
  mealPeak: 3.5, // Max rise from meal
  mealPeakTime: 60, // Minutes to peak
  mealDecayTime: 180, // Minutes to return to baseline
  // Dawn phenomenon (early morning rise)
  dawnRiseStart: 4, // Hour
  dawnRiseEnd: 8, // Hour
  dawnRiseAmount: 1.5,
  // Noise
  measurementNoise: 0.3,
};

// Utility functions
function randomInRange(min: number, max: number): number {
  return Math.random() * (max - min) + min;
}

function randomNormal(mean: number, stdDev: number): number {
  // Box-Muller transform for normal distribution
  const u1 = Math.random();
  const u2 = Math.random();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return mean + z * stdDev;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function roundTo1Decimal(value: number): number {
  return Math.round(value * 10) / 10;
}

/**
 * Calculate blood glucose at a given time based on various factors
 */
function calculateBG(
  timestamp: Date,
  mealTimes: Date[],
  insulinTimes: Array<{ time: Date; type: 'bolus' | 'basal'; units: number }>,
  exerciseTimes: Array<{ time: Date; duration: number; intensity: 'low' | 'moderate' | 'high' }>
): number {
  const hour = timestamp.getHours();
  const minuteOfDay = hour * 60 + timestamp.getMinutes();

  // Start with baseline
  let bg = BG_PARAMS.baselineFasting + randomNormal(0, BG_PARAMS.baselineVariation * 0.3);

  // Dawn phenomenon effect (higher BG in early morning)
  if (hour >= BG_PARAMS.dawnRiseStart && hour <= BG_PARAMS.dawnRiseEnd) {
    const dawnProgress =
      (hour - BG_PARAMS.dawnRiseStart) / (BG_PARAMS.dawnRiseEnd - BG_PARAMS.dawnRiseStart);
    const dawnEffect = Math.sin(dawnProgress * Math.PI) * BG_PARAMS.dawnRiseAmount;
    bg += dawnEffect;
  }

  // Meal effects (BG rise after eating)
  for (const mealTime of mealTimes) {
    const minutesSinceMeal = (timestamp.getTime() - mealTime.getTime()) / (1000 * 60);
    if (minutesSinceMeal > 0 && minutesSinceMeal < BG_PARAMS.mealDecayTime) {
      // Meal causes a rise that peaks and then decays
      const peakPhase = minutesSinceMeal / BG_PARAMS.mealPeakTime;
      const decayPhase = (minutesSinceMeal - BG_PARAMS.mealPeakTime) / (BG_PARAMS.mealDecayTime - BG_PARAMS.mealPeakTime);

      let mealEffect = 0;
      if (minutesSinceMeal < BG_PARAMS.mealPeakTime) {
        // Rising phase
        mealEffect = BG_PARAMS.mealPeak * Math.sin((peakPhase * Math.PI) / 2);
      } else {
        // Decay phase
        mealEffect = BG_PARAMS.mealPeak * Math.cos((decayPhase * Math.PI) / 2);
      }

      // Add some randomness to meal effect
      mealEffect *= randomInRange(0.7, 1.3);
      bg += Math.max(0, mealEffect);
    }
  }

  // Insulin effects (BG lowering)
  for (const insulin of insulinTimes) {
    const minutesSinceInsulin = (timestamp.getTime() - insulin.time.getTime()) / (1000 * 60);

    if (insulin.type === 'bolus' && minutesSinceInsulin > 0 && minutesSinceInsulin < 240) {
      // Bolus insulin peaks at ~60-90 min, active for ~4 hours
      const peakTime = 75;
      const duration = 240;
      const effect = insulin.units * 0.15; // ~0.15 mmol/L drop per unit

      if (minutesSinceInsulin < peakTime) {
        bg -= effect * Math.sin((minutesSinceInsulin / peakTime) * Math.PI / 2);
      } else {
        const decayProgress = (minutesSinceInsulin - peakTime) / (duration - peakTime);
        bg -= effect * Math.cos(decayProgress * Math.PI / 2);
      }
    }

    if (insulin.type === 'basal' && minutesSinceInsulin > 0 && minutesSinceInsulin < 720) {
      // Basal insulin has a flat profile over ~12 hours
      const effect = insulin.units * 0.02; // Smaller ongoing effect
      bg -= effect;
    }
  }

  // Exercise effects (BG lowering during and after)
  for (const exercise of exerciseTimes) {
    const minutesSinceExercise = (timestamp.getTime() - exercise.time.getTime()) / (1000 * 60);
    const exerciseEnd = exercise.duration;

    // During exercise and up to 2 hours after
    if (minutesSinceExercise > -30 && minutesSinceExercise < exerciseEnd + 120) {
      const intensityFactor = exercise.intensity === 'high' ? 1.5 : exercise.intensity === 'moderate' ? 1.0 : 0.5;
      const durationFactor = exercise.duration / 60;
      const effect = intensityFactor * durationFactor * 1.5;

      if (minutesSinceExercise < exerciseEnd) {
        // During exercise - gradual drop
        const progress = minutesSinceExercise / exerciseEnd;
        bg -= effect * progress;
      } else {
        // After exercise - continued sensitivity
        const afterProgress = (minutesSinceExercise - exerciseEnd) / 120;
        bg -= effect * (1 - afterProgress * 0.5);
      }
    }
  }

  // Add measurement noise (CGM isn't perfectly accurate)
  bg += randomNormal(0, BG_PARAMS.measurementNoise);

  // Clamp to physiological limits
  bg = clamp(bg, BG_PARAMS.minPhysio, BG_PARAMS.maxPhysio);

  return roundTo1Decimal(bg);
}

/**
 * Generate all blood glucose readings for a given time range
 */
function generateBGReadings(
  startDate: Date,
  endDate: Date,
  mealTimes: Date[],
  insulinTimes: Array<{ time: Date; type: 'bolus' | 'basal'; units: number }>,
  exerciseTimes: Array<{ time: Date; duration: number; intensity: 'low' | 'moderate' | 'high' }>
): PhysiologicalEvent[] {
  const events: PhysiologicalEvent[] = [];
  const intervalMs = 5 * 60 * 1000; // 5 minutes

  let currentTime = new Date(startDate);
  while (currentTime <= endDate) {
    const bg = calculateBG(currentTime, mealTimes, insulinTimes, exerciseTimes);
    const timestamp = currentTime.toISOString();

    events.push({
      id: randomUUID(),
      timestamp,
      eventType: 'bsl',
      value: bg,
      metadata: {
        unit: 'mmol/L',
        source: 'csv-import',
        device: 'Test Data Generator',
      },
      createdAt: timestamp,
      updatedAt: timestamp,
      synced: false,
    });

    currentTime = new Date(currentTime.getTime() + intervalMs);
  }

  return events;
}

/**
 * Generate insulin events from the insulin schedule
 */
function generateInsulinEvents(
  insulinTimes: Array<{ time: Date; type: 'bolus' | 'basal'; units: number; reason?: string }>
): PhysiologicalEvent[] {
  return insulinTimes.map((insulin) => {
    const timestamp = insulin.time.toISOString();
    return {
      id: randomUUID(),
      timestamp,
      eventType: 'insulin' as const,
      value: insulin.units,
      metadata: {
        type: insulin.type,
        ...(insulin.reason && { reason: insulin.reason }),
      },
      createdAt: timestamp,
      updatedAt: timestamp,
      synced: false,
    };
  });
}

/**
 * Generate exercise events from the exercise schedule
 */
function generateExerciseEvents(
  exerciseTimes: Array<{
    time: Date;
    duration: number;
    intensity: 'low' | 'moderate' | 'high';
    category: 'swimming' | 'cycling' | 'walking';
    exerciseType: string;
  }>
): PhysiologicalEvent[] {
  return exerciseTimes.map((exercise) => {
    const timestamp = exercise.time.toISOString();

    // Estimate calories burned based on intensity and duration
    const caloriesPerMinute =
      exercise.intensity === 'high' ? 12 : exercise.intensity === 'moderate' ? 8 : 5;
    const caloriesBurned = Math.round(caloriesPerMinute * exercise.duration * randomInRange(0.9, 1.1));

    return {
      id: randomUUID(),
      timestamp,
      eventType: 'exercise' as const,
      value: exercise.duration,
      metadata: {
        intensity: exercise.intensity,
        exerciseType: exercise.exerciseType,
        category: exercise.category,
        durationMinutes: exercise.duration,
        caloriesBurned,
        source: 'manual',
      },
      createdAt: timestamp,
      updatedAt: timestamp,
      synced: false,
    };
  });
}

/**
 * Generate test data for 1 month
 */
function generateTestData(): TestDataOutput {
  const now = new Date();
  // End a few minutes ago
  const endDate = new Date(now.getTime() - 3 * 60 * 1000);
  // Start 1 month before
  const startDate = new Date(endDate);
  startDate.setMonth(startDate.getMonth() - 1);

  console.log(`Generating data from ${startDate.toISOString()} to ${endDate.toISOString()}`);

  const mealTimes: Date[] = [];
  const insulinTimes: Array<{ time: Date; type: 'bolus' | 'basal'; units: number; reason?: string }> = [];
  const exerciseTimes: Array<{
    time: Date;
    duration: number;
    intensity: 'low' | 'moderate' | 'high';
    category: 'swimming' | 'cycling' | 'walking';
    exerciseType: string;
  }> = [];

  // Generate meal, insulin, and exercise schedules for each day
  let currentDay = new Date(startDate);
  while (currentDay <= endDate) {
    const dayStart = new Date(currentDay);
    dayStart.setHours(0, 0, 0, 0);

    // Breakfast ~7-9am
    const breakfast = new Date(dayStart);
    breakfast.setHours(7 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 60));
    mealTimes.push(breakfast);

    // Lunch ~12-2pm
    const lunch = new Date(dayStart);
    lunch.setHours(12 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 60));
    mealTimes.push(lunch);

    // Dinner ~6-8pm
    const dinner = new Date(dayStart);
    dinner.setHours(18 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 60));
    mealTimes.push(dinner);

    // Occasional snacks (~30% chance, afternoon)
    const hasSnack = Math.random() < 0.3;
    let snackTime: Date | null = null;
    if (hasSnack) {
      snackTime = new Date(dayStart);
      snackTime.setHours(15 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 60));
      mealTimes.push(snackTime);
    }

    // Occasional liquor (~15% chance, evening)
    const hasLiquor = Math.random() < 0.15;
    let liquorTime: Date | null = null;
    if (hasLiquor) {
      liquorTime = new Date(dayStart);
      liquorTime.setHours(20 + Math.floor(Math.random() * 3), Math.floor(Math.random() * 60));
      mealTimes.push(liquorTime);
    }

    // ===== BASAL INSULIN =====
    // 7am basal (15 units, with small timing variation)
    const basalMorning = new Date(dayStart);
    basalMorning.setHours(7, Math.floor(Math.random() * 15));
    insulinTimes.push({ time: basalMorning, type: 'basal', units: 15 });

    // 7pm basal (15 units, with small timing variation)
    const basalEvening = new Date(dayStart);
    basalEvening.setHours(19, Math.floor(Math.random() * 15));
    insulinTimes.push({ time: basalEvening, type: 'basal', units: 15 });

    // ===== BOLUS INSULIN =====
    // Bolus for breakfast (4-8 units, ~10 min before)
    insulinTimes.push({
      time: new Date(breakfast.getTime() - 10 * 60000),
      type: 'bolus',
      units: Math.round(randomInRange(4, 8)),
      reason: 'meal',
    });

    // Bolus for lunch (5-10 units, ~10 min before)
    insulinTimes.push({
      time: new Date(lunch.getTime() - 10 * 60000),
      type: 'bolus',
      units: Math.round(randomInRange(5, 10)),
      reason: 'meal',
    });

    // Bolus for dinner (6-12 units, ~10 min before)
    insulinTimes.push({
      time: new Date(dinner.getTime() - 10 * 60000),
      type: 'bolus',
      units: Math.round(randomInRange(6, 12)),
      reason: 'meal',
    });

    // Bolus for snack if present (2-4 units)
    if (snackTime) {
      insulinTimes.push({
        time: new Date(snackTime.getTime() - 5 * 60000),
        type: 'bolus',
        units: Math.round(randomInRange(2, 4)),
        reason: 'snack',
      });
    }

    // Bolus for liquor if present (1-3 units for mixers/carbs)
    if (liquorTime) {
      insulinTimes.push({
        time: new Date(liquorTime.getTime() - 5 * 60000),
        type: 'bolus',
        units: Math.round(randomInRange(1, 3)),
        reason: 'liquor',
      });
    }

    // Exercise ~3-4 times per week
    if (Math.random() < 0.5) {
      const exerciseHour = Math.random() < 0.5 ? 7 : 18; // Morning or evening
      const exerciseTime = new Date(dayStart);
      exerciseTime.setHours(exerciseHour, Math.floor(Math.random() * 30));

      // Random exercise type
      const exerciseRoll = Math.random();
      if (exerciseRoll < 0.33) {
        // Walk - 40 minutes, low intensity
        exerciseTimes.push({
          time: exerciseTime,
          duration: 40,
          intensity: 'low',
          category: 'walking',
          exerciseType: 'Walk',
        });
      } else if (exerciseRoll < 0.66) {
        // Cycle - 20 minutes, medium intensity
        exerciseTimes.push({
          time: exerciseTime,
          duration: 20,
          intensity: 'moderate',
          category: 'cycling',
          exerciseType: 'Cycle',
        });
      } else {
        // Swim - 1 hour, high intensity
        exerciseTimes.push({
          time: exerciseTime,
          duration: 60,
          intensity: 'high',
          category: 'swimming',
          exerciseType: 'Swim',
        });
      }
    }

    currentDay.setDate(currentDay.getDate() + 1);
  }

  // Generate BG readings
  const bgEvents = generateBGReadings(startDate, endDate, mealTimes, insulinTimes, exerciseTimes);

  // Generate insulin events
  const insulinEvents = generateInsulinEvents(insulinTimes);

  // Generate exercise events
  const exerciseEvents = generateExerciseEvents(exerciseTimes);

  // Combine all events
  const allEvents = [...bgEvents, ...insulinEvents, ...exerciseEvents];

  // Sort by timestamp
  allEvents.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());

  console.log(`Generated ${bgEvents.length} BG readings`);
  console.log(
    `BG range: ${Math.min(...bgEvents.map((e) => e.value)).toFixed(1)} - ${Math.max(...bgEvents.map((e) => e.value)).toFixed(1)} mmol/L`
  );

  // Count insulin events by type
  const basalCount = insulinEvents.filter((e) => e.metadata.type === 'basal').length;
  const bolusCount = insulinEvents.filter((e) => e.metadata.type === 'bolus').length;
  console.log(`Generated ${insulinEvents.length} insulin events (${basalCount} basal, ${bolusCount} bolus)`);

  // Count exercise events by type
  const swimCount = exerciseEvents.filter((e) => e.metadata.category === 'swimming').length;
  const cycleCount = exerciseEvents.filter((e) => e.metadata.category === 'cycling').length;
  const walkCount = exerciseEvents.filter((e) => e.metadata.category === 'walking').length;
  console.log(
    `Generated ${exerciseEvents.length} exercise events (${swimCount} swims, ${cycleCount} cycles, ${walkCount} walks)`
  );

  return {
    version: '1.0',
    type: 'backup',
    createdAt: new Date().toISOString(),
    count: allEvents.length,
    events: allEvents,
  };
}

// Main execution
const testData = generateTestData();

// Write to static directory for easy access during dev
const outputDir = join(__dirname, '..', 'static');
if (!existsSync(outputDir)) {
  mkdirSync(outputDir, { recursive: true });
}

const outputPath = join(outputDir, 'test-data.json');
writeFileSync(outputPath, JSON.stringify(testData, null, 2));

console.log(`\nTest data written to: ${outputPath}`);
console.log(`Total events: ${testData.count}`);
console.log(`\nTo import in the app, use the backup restore feature or import this file directly.`);
