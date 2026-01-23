/**
 * Circadian (Time-of-Day) Sensitivity Model
 *
 * Models how insulin sensitivity and glucose metabolism vary throughout the day.
 *
 * Key phenomena:
 * - Dawn Phenomenon: Blood glucose rises 3-6am due to growth hormone, cortisol
 * - Dusk Effect: Some people have insulin resistance in late afternoon
 * - Overnight: Generally more insulin sensitive during sleep
 * - Post-meal: Insulin sensitivity varies by meal timing
 *
 * References:
 * - Porcellati et al. - Dawn Phenomenon and the Somogyi Effect
 * - Clinical guidelines for circadian insulin dosing
 */

import type { CircadianFactors } from '../../types/modeling';

/**
 * Default circadian sensitivity pattern
 * Values < 1.0 = more insulin sensitive (need less insulin)
 * Values > 1.0 = more insulin resistant (need more insulin)
 *
 * Based on average patterns; individuals vary significantly
 */
export const DEFAULT_CIRCADIAN_PATTERN: Record<number, number> = {
  0: 0.95, // Midnight - moderate sensitivity
  1: 0.9, // 1am - good sensitivity
  2: 0.85, // 2am - high sensitivity (sleep)
  3: 0.85, // 3am - high sensitivity
  4: 0.9, // 4am - dawn phenomenon starting
  5: 1.0, // 5am - increasing resistance
  6: 1.15, // 6am - dawn effect peak
  7: 1.2, // 7am - morning resistance
  8: 1.15, // 8am - still resistant
  9: 1.1, // 9am - improving
  10: 1.0, // 10am - baseline
  11: 1.0, // 11am - baseline
  12: 1.05, // Noon - slight lunch resistance
  13: 1.0, // 1pm - baseline
  14: 0.95, // 2pm - afternoon dip
  15: 0.95, // 3pm - good sensitivity
  16: 1.0, // 4pm - baseline
  17: 1.05, // 5pm - pre-dinner
  18: 1.1, // 6pm - dinner resistance
  19: 1.05, // 7pm - evening
  20: 1.0, // 8pm - baseline
  21: 0.95, // 9pm - improving
  22: 0.9, // 10pm - evening sensitivity
  23: 0.95 // 11pm - good sensitivity
};

/**
 * Dawn phenomenon intensity factors
 * Separate from general sensitivity - specifically models morning glucose rise
 */
export const DAWN_PHENOMENON_PATTERN: Record<number, number> = {
  0: 0,
  1: 0,
  2: 0,
  3: 0.2, // Dawn effect begins
  4: 0.5,
  5: 0.8,
  6: 1.0, // Peak dawn effect
  7: 0.8,
  8: 0.4,
  9: 0.1,
  10: 0,
  11: 0,
  12: 0,
  13: 0,
  14: 0,
  15: 0,
  16: 0,
  17: 0,
  18: 0,
  19: 0,
  20: 0,
  21: 0,
  22: 0,
  23: 0
};

/**
 * Calculate circadian factors for a given time
 *
 * @param atTime - Time to calculate factors for
 * @param userAdjustments - Optional user-specific adjustments
 * @returns Circadian factors
 */
export function calculateCircadianFactors(
  atTime: Date = new Date(),
  userAdjustments?: Partial<Record<number, number>>
): CircadianFactors {
  const hour = atTime.getHours();

  // Get base sensitivity
  let insulinSensitivity = DEFAULT_CIRCADIAN_PATTERN[hour] || 1.0;

  // Apply user adjustments if provided
  if (userAdjustments && userAdjustments[hour] !== undefined) {
    insulinSensitivity *= userAdjustments[hour]!;
  }

  // Get dawn effect
  const dawnEffect = DAWN_PHENOMENON_PATTERN[hour] || 0;

  // Combined factor includes dawn effect as additional resistance
  const combinedFactor = insulinSensitivity + dawnEffect * 0.1;

  return {
    hour,
    insulinSensitivity,
    dawnEffect,
    combinedFactor
  };
}

/**
 * Interpolate circadian factors between hours for smoother curves
 *
 * @param atTime - Time to interpolate for
 * @param userAdjustments - Optional user adjustments
 * @returns Interpolated circadian factors
 */
export function interpolateCircadianFactors(
  atTime: Date = new Date(),
  userAdjustments?: Partial<Record<number, number>>
): CircadianFactors {
  const hour = atTime.getHours();
  const minute = atTime.getMinutes();
  const fractionalHour = minute / 60;

  const currentHour = hour;
  const nextHour = (hour + 1) % 24;

  const currentFactors = calculateCircadianFactors(
    new Date(atTime.getFullYear(), atTime.getMonth(), atTime.getDate(), currentHour),
    userAdjustments
  );
  const nextFactors = calculateCircadianFactors(
    new Date(atTime.getFullYear(), atTime.getMonth(), atTime.getDate(), nextHour),
    userAdjustments
  );

  // Linear interpolation
  const interpolate = (current: number, next: number): number =>
    current + (next - current) * fractionalHour;

  return {
    hour: currentHour,
    insulinSensitivity: interpolate(
      currentFactors.insulinSensitivity,
      nextFactors.insulinSensitivity
    ),
    dawnEffect: interpolate(currentFactors.dawnEffect, nextFactors.dawnEffect),
    combinedFactor: interpolate(currentFactors.combinedFactor, nextFactors.combinedFactor)
  };
}

/**
 * Adjust insulin dose for time of day
 *
 * @param baseDose - Calculated dose without time adjustment
 * @param atTime - Time of dosing
 * @param userAdjustments - Optional user adjustments
 * @returns Adjusted dose
 */
export function adjustDoseForTimeOfDay(
  baseDose: number,
  atTime: Date = new Date(),
  userAdjustments?: Partial<Record<number, number>>
): { adjustedDose: number; adjustment: number; reason: string } {
  const factors = interpolateCircadianFactors(atTime, userAdjustments);

  const adjustedDose = baseDose * factors.combinedFactor;
  const adjustment = adjustedDose - baseDose;

  let reason = '';
  if (factors.dawnEffect > 0.5) {
    reason = 'Dawn phenomenon: increased morning insulin resistance';
  } else if (factors.insulinSensitivity < 0.95) {
    reason = 'Higher insulin sensitivity at this time';
  } else if (factors.insulinSensitivity > 1.05) {
    reason = 'Reduced insulin sensitivity at this time';
  } else {
    reason = 'Near baseline sensitivity';
  }

  return { adjustedDose, adjustment, reason };
}

/**
 * Estimate baseline BSL drift due to circadian rhythm
 * Without any food or insulin, BSL will naturally fluctuate
 *
 * @param startTime - Start of period
 * @param endTime - End of period
 * @returns Expected BSL change in mmol/L
 */
export function estimateCircadianBSLDrift(startTime: Date, endTime: Date): number {
  // Integrate dawn effect over the period
  // Note: fractional hours available for future enhanced algorithms
  // const startHour = startTime.getHours() + startTime.getMinutes() / 60;
  // const endHour = endTime.getHours() + endTime.getMinutes() / 60;

  let totalDawnEffect = 0;
  const steps = 12; // 5-minute steps

  for (let i = 0; i < steps; i++) {
    const fraction = i / steps;
    const time = new Date(
      startTime.getTime() + fraction * (endTime.getTime() - startTime.getTime())
    );
    const factors = interpolateCircadianFactors(time);
    totalDawnEffect += factors.dawnEffect / steps;
  }

  // Dawn effect of 1.0 corresponds to roughly 1-2 mmol/L rise per hour
  const hoursElapsed = (endTime.getTime() - startTime.getTime()) / (1000 * 60 * 60);
  return totalDawnEffect * 1.5 * hoursElapsed;
}

/**
 * Generate circadian sensitivity curve for visualisation
 *
 * @param userAdjustments - Optional user adjustments
 * @returns Array of sensitivity values for each hour
 */
export function generateCircadianCurve(userAdjustments?: Partial<Record<number, number>>): Array<{
  hour: number;
  insulinSensitivity: number;
  dawnEffect: number;
  combinedFactor: number;
}> {
  const curve: Array<{
    hour: number;
    insulinSensitivity: number;
    dawnEffect: number;
    combinedFactor: number;
  }> = [];

  for (let hour = 0; hour < 24; hour++) {
    const time = new Date();
    time.setHours(hour, 0, 0, 0);
    const factors = calculateCircadianFactors(time, userAdjustments);
    curve.push(factors);
  }

  return curve;
}

/**
 * Suggest basal rate adjustments based on BSL patterns
 * Analyzes overnight BSL data to detect dawn phenomenon intensity
 *
 * @param overnightBSLs - Array of BSL readings from overnight
 * @returns Suggested adjustments
 */
export function analyzeOvernightPattern(overnightBSLs: Array<{ timestamp: Date; value: number }>): {
  dawnPhenomenonDetected: boolean;
  suggestedAdjustments: Partial<Record<number, number>>;
  analysis: string;
} {
  if (overnightBSLs.length < 3) {
    return {
      dawnPhenomenonDetected: false,
      suggestedAdjustments: {},
      analysis: 'Insufficient data for overnight analysis'
    };
  }

  // Sort by timestamp
  const sorted = [...overnightBSLs].sort(
    (a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
  );

  // Look for rise between 3am and 7am
  const earlyMorning = sorted.filter((r) => {
    const hour = new Date(r.timestamp).getHours();
    return hour >= 3 && hour <= 7;
  });

  const preDawn = sorted.filter((r) => {
    const hour = new Date(r.timestamp).getHours();
    return hour >= 0 && hour <= 3;
  });

  if (earlyMorning.length === 0 || preDawn.length === 0) {
    return {
      dawnPhenomenonDetected: false,
      suggestedAdjustments: {},
      analysis: 'No data in dawn window'
    };
  }

  const avgPreDawn = preDawn.reduce((sum, r) => sum + r.value, 0) / preDawn.length;
  const avgDawn = earlyMorning.reduce((sum, r) => sum + r.value, 0) / earlyMorning.length;
  const rise = avgDawn - avgPreDawn;

  if (rise > 1.5) {
    // Significant dawn phenomenon
    const intensity = Math.min(rise / 3, 1); // Cap at 3 mmol/L rise = full intensity

    return {
      dawnPhenomenonDetected: true,
      suggestedAdjustments: {
        4: 1 + intensity * 0.15,
        5: 1 + intensity * 0.2,
        6: 1 + intensity * 0.25,
        7: 1 + intensity * 0.2,
        8: 1 + intensity * 0.1
      },
      analysis: `Dawn phenomenon detected: average rise of ${rise.toFixed(1)} mmol/L. Consider increasing basal 4-8am.`
    };
  }

  return {
    dawnPhenomenonDetected: false,
    suggestedAdjustments: {},
    analysis: `No significant dawn phenomenon. BSL change: ${rise.toFixed(1)} mmol/L`
  };
}
