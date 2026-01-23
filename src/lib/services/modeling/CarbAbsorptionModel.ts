/**
 * Carbohydrate Absorption Model
 *
 * Models the absorption of carbohydrates based on glycemic index.
 * Uses exponential curves to simulate glucose appearance in blood.
 *
 * References:
 * - High GI foods: peak 30-45min, duration 2-3hr
 * - Medium GI foods: peak 45-60min, duration 3-4hr
 * - Low GI foods: peak 60-90min, duration 4-5hr
 */

import type { PhysiologicalEvent, MealMetadata } from '../../types/events';
import type {
  CarbAbsorptionParams,
  CarbAbsorptionPoint,
  ActiveCarbsResult,
  MealContribution
} from '../../types/modeling';

/**
 * Default glycemic index assumptions by food type keywords
 */
export const GI_ESTIMATES: Record<string, number> = {
  // High GI (70+)
  bread: 75,
  rice: 73,
  potato: 78,
  sugar: 100,
  glucose: 100,
  candy: 85,
  soda: 90,
  juice: 80,
  cereal: 75,
  // Medium GI (56-69)
  pasta: 55,
  oatmeal: 58,
  fruit: 55,
  banana: 62,
  pizza: 60,
  // Low GI (<55)
  beans: 30,
  lentils: 28,
  nuts: 20,
  vegetables: 15,
  dairy: 35,
  apple: 38,
  // Defaults
  default: 60, // Medium if unknown
  mixed: 55 // Mixed meals tend to be lower GI
};

/**
 * Calculate absorption parameters based on glycemic index
 */
export function getAbsorptionParams(glycemicIndex: number): CarbAbsorptionParams {
  // Normalise GI to 0-100 range
  const gi = Math.max(0, Math.min(100, glycemicIndex));

  // Higher GI = faster absorption
  // Map GI to peak time: GI 100 -> 30min, GI 0 -> 120min
  const peakMinutes = 120 - (gi / 100) * 90;

  // Duration scales with GI inversely
  // GI 100 -> 120min, GI 0 -> 300min
  const durationMinutes = 120 + ((100 - gi) / 100) * 180;

  // Half-life is roughly 1/3 of duration for the decay phase
  const halfLifeMinutes = durationMinutes / 3;

  return {
    glycemicIndex: gi,
    peakMinutes,
    durationMinutes,
    halfLifeMinutes
  };
}

/**
 * Estimate glycemic index from meal description
 */
export function estimateGlycemicIndex(description?: string): number {
  if (!description) return GI_ESTIMATES.default;

  const lowerDesc = description.toLowerCase();

  // Check for specific keywords
  for (const [keyword, gi] of Object.entries(GI_ESTIMATES)) {
    if (lowerDesc.includes(keyword)) {
      return gi;
    }
  }

  // Check for modifiers
  if (lowerDesc.includes('whole grain') || lowerDesc.includes('wholegrain')) {
    return 50;
  }
  if (lowerDesc.includes('white')) {
    return 70;
  }
  if (lowerDesc.includes('fiber') || lowerDesc.includes('fibre')) {
    return 45;
  }

  return GI_ESTIMATES.default;
}

/**
 * Calculate carb absorption at a given time point
 * Uses a gamma distribution approximation for realistic absorption curves
 *
 * @param minutesFromMeal - Minutes since meal was eaten
 * @param totalCarbs - Total carbs in grams
 * @param glycemicIndex - Glycemic index of the meal
 * @returns Absorption point with rate and carbs on board
 */
export function calculateCarbAbsorption(
  minutesFromMeal: number,
  totalCarbs: number,
  glycemicIndex: number = GI_ESTIMATES.default
): CarbAbsorptionPoint {
  const params = getAbsorptionParams(glycemicIndex);

  if (minutesFromMeal < 0) {
    return {
      minutesFromMeal,
      absorptionRate: 0,
      carbsOnBoard: totalCarbs,
      carbsAbsorbed: 0
    };
  }

  if (minutesFromMeal >= params.durationMinutes) {
    return {
      minutesFromMeal,
      absorptionRate: 0,
      carbsOnBoard: 0,
      carbsAbsorbed: totalCarbs
    };
  }

  // Use a gamma-like distribution for absorption curve
  // f(t) = (t/τ)^k * e^(-t/τ) / Γ(k+1)
  // Simplified: rising phase then exponential decay

  const t = minutesFromMeal;
  const tPeak = params.peakMinutes;
  const τ = params.halfLifeMinutes;

  // Shape parameter based on peak time
  const k = tPeak / τ;

  // Calculate absorption rate (normalised)
  let rate: number;
  if (t < tPeak) {
    // Rising phase - power function
    rate = Math.pow(t / tPeak, k);
  } else {
    // Decay phase - exponential
    rate = Math.exp(-((t - tPeak) / τ));
  }

  // Absorption rate in grams per hour
  // Peak rate is designed to absorb most carbs within duration
  const peakRateGramsPerHour = (totalCarbs * 2) / (params.durationMinutes / 60);
  const absorptionRate = rate * peakRateGramsPerHour;

  // Calculate carbs absorbed using numerical integration approximation
  // For simplicity, use cumulative distribution based on rate
  let carbsAbsorbed: number;
  if (t < tPeak) {
    // Rising phase - integral of power function
    carbsAbsorbed =
      (totalCarbs * Math.pow(t / tPeak, k + 1) * tPeak) / ((k + 1) * params.durationMinutes);
  } else {
    // Peak and decay phase
    const absorbedAtPeak = totalCarbs * 0.4; // ~40% absorbed by peak
    const remainingAtPeak = totalCarbs - absorbedAtPeak;
    const decayFraction = 1 - Math.exp(-((t - tPeak) / τ));
    carbsAbsorbed = absorbedAtPeak + remainingAtPeak * decayFraction;
  }

  // Ensure within bounds
  carbsAbsorbed = Math.max(0, Math.min(totalCarbs, carbsAbsorbed));
  const carbsOnBoard = totalCarbs - carbsAbsorbed;

  return {
    minutesFromMeal,
    absorptionRate: Math.max(0, absorptionRate),
    carbsOnBoard: Math.max(0, carbsOnBoard),
    carbsAbsorbed
  };
}

/**
 * Generate full absorption curve for visualisation
 *
 * @param totalCarbs - Total carbs in grams
 * @param glycemicIndex - Glycemic index
 * @param resolutionMinutes - Time resolution
 * @returns Array of absorption points
 */
export function generateAbsorptionCurve(
  totalCarbs: number,
  glycemicIndex: number = GI_ESTIMATES.default,
  resolutionMinutes: number = 5
): CarbAbsorptionPoint[] {
  const params = getAbsorptionParams(glycemicIndex);
  const points: CarbAbsorptionPoint[] = [];

  for (let t = 0; t <= params.durationMinutes; t += resolutionMinutes) {
    points.push(calculateCarbAbsorption(t, totalCarbs, glycemicIndex));
  }

  return points;
}

/**
 * Calculate active carbs from multiple meals
 *
 * @param mealEvents - Array of meal events
 * @param atTime - Time to calculate COB at
 * @returns Active carbs result with total COB and breakdown
 */
export function calculateActiveCarbs(
  mealEvents: PhysiologicalEvent[],
  atTime: Date = new Date()
): ActiveCarbsResult {
  const mealContributions: MealContribution[] = [];
  let totalCOB = 0;
  let totalAbsorptionRate = 0;
  let latestAbsorptionComplete = atTime;

  for (const event of mealEvents) {
    if (event.eventType !== 'meal') continue;

    const metadata = event.metadata as MealMetadata | undefined;
    const carbs = metadata?.carbs ?? event.value;

    // Skip meals with no carbs
    if (!carbs || carbs <= 0) continue;

    const mealTime = new Date(event.timestamp);
    const minutesSinceMeal = (atTime.getTime() - mealTime.getTime()) / (1000 * 60);

    // Skip future meals
    if (minutesSinceMeal < 0) continue;

    // Estimate GI from meal description
    const glycemicIndex = estimateGlycemicIndex(metadata?.description);
    const params = getAbsorptionParams(glycemicIndex);

    // Skip if meal is fully absorbed
    if (minutesSinceMeal >= params.durationMinutes) continue;

    const absorption = calculateCarbAbsorption(minutesSinceMeal, carbs, glycemicIndex);

    totalCOB += absorption.carbsOnBoard;
    totalAbsorptionRate += absorption.absorptionRate;

    // Calculate when this meal will be fully absorbed
    const remainingMinutes = params.durationMinutes - minutesSinceMeal;
    const absorptionComplete = new Date(atTime.getTime() + remainingMinutes * 60 * 1000);
    if (absorptionComplete > latestAbsorptionComplete) {
      latestAbsorptionComplete = absorptionComplete;
    }

    mealContributions.push({
      mealId: event.id,
      timestamp: mealTime,
      originalCarbs: carbs,
      remainingCOB: absorption.carbsOnBoard,
      absorptionRate: absorption.absorptionRate,
      minutesSinceMeal,
      glycemicIndex
    });
  }

  return {
    totalCOB,
    absorptionRate: totalAbsorptionRate,
    mealContributions,
    estimatedAbsorptionComplete: latestAbsorptionComplete
  };
}

/**
 * Estimate BSL impact from active carbs
 *
 * @param cob - Carbs on board in grams
 * @param insulinToCarbRatio - Grams of carbs covered by 1 unit of insulin
 * @param correctionFactor - BSL change per unit of insulin (mmol/L)
 * @returns Expected BSL rise in mmol/L
 */
export function estimateCarbBSLEffect(
  cob: number,
  insulinToCarbRatio: number,
  correctionFactor: number
): number {
  // Carbs that would need X units to cover = X * correction factor BSL rise
  const unitsNeeded = cob / insulinToCarbRatio;
  return unitsNeeded * correctionFactor;
}

/**
 * Project carb absorption over time for charting
 *
 * @param mealEvents - Meal events to model
 * @param startTime - Start of projection
 * @param endTime - End of projection
 * @param resolutionMinutes - Time step in minutes
 * @returns Array of COB values over time
 */
export function projectCarbAbsorption(
  mealEvents: PhysiologicalEvent[],
  startTime: Date,
  endTime: Date,
  resolutionMinutes: number = 5
): Array<{ timestamp: Date; cob: number; absorptionRate: number }> {
  const projections: Array<{ timestamp: Date; cob: number; absorptionRate: number }> = [];
  const stepMs = resolutionMinutes * 60 * 1000;

  for (let t = startTime.getTime(); t <= endTime.getTime(); t += stepMs) {
    const atTime = new Date(t);
    const result = calculateActiveCarbs(mealEvents, atTime);
    projections.push({
      timestamp: atTime,
      cob: result.totalCOB,
      absorptionRate: result.absorptionRate
    });
  }

  return projections;
}
