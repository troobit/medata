/**
 * Alcohol Metabolism Model
 *
 * Models alcohol absorption, metabolism, and effects on insulin sensitivity.
 *
 * Key physiological facts:
 * - 1 standard drink = 10g pure alcohol (Australian standard)
 * - Average metabolism: 7-10g/hour (varies by body weight, sex, liver function)
 * - Alcohol absorption: 20% stomach, 80% small intestine
 * - Peak BAC: 30-90 minutes depending on drink type and food
 * - Alcohol increases insulin sensitivity for up to 24 hours
 * - Can cause delayed hypoglycemia 6-12 hours after drinking
 *
 * References:
 * - Widmark formula for BAC estimation
 * - Clinical studies on alcohol and diabetes management
 */

import type { AlcoholType, PhysiologicalEvent, MealMetadata } from '../../types/events';
import type {
  AlcoholMetabolismParams,
  BloodAlcoholResult,
  DrinkContribution
} from '../../types/modeling';

/**
 * Standard drink definitions (Australian standard = 10g alcohol)
 */
export const STANDARD_DRINK_GRAMS = 10;

/**
 * Alcohol metabolism parameters by drink type
 * Different drinks absorb at different rates due to:
 * - Carbonation (faster absorption)
 * - Alcohol concentration (spirits faster if neat)
 * - Mixer volume (dilution slows absorption)
 */
export const ALCOHOL_PARAMS: Record<AlcoholType, AlcoholMetabolismParams> = {
  beer: {
    drinkType: 'beer',
    absorptionHalfLifeMinutes: 20, // Moderate - carbonation helps
    eliminationRateGramsPerHour: 8, // Average
    peakTimeMinutes: 45, // Medium peak time
    insulinSensitivityModifier: 0.85, // 15% increase in sensitivity
    sensitivityEffectDurationHours: 12
  },
  wine: {
    drinkType: 'wine',
    absorptionHalfLifeMinutes: 25, // Slightly slower
    eliminationRateGramsPerHour: 8,
    peakTimeMinutes: 50,
    insulinSensitivityModifier: 0.8, // 20% increase (wine has more effect)
    sensitivityEffectDurationHours: 14
  },
  spirit: {
    drinkType: 'spirit',
    absorptionHalfLifeMinutes: 15, // Fast if neat
    eliminationRateGramsPerHour: 8,
    peakTimeMinutes: 30, // Quick peak
    insulinSensitivityModifier: 0.75, // 25% increase
    sensitivityEffectDurationHours: 16
  },
  mixed: {
    drinkType: 'mixed',
    absorptionHalfLifeMinutes: 25, // Mixers slow it down
    eliminationRateGramsPerHour: 8,
    peakTimeMinutes: 60, // Slower peak
    insulinSensitivityModifier: 0.8, // 20% increase
    sensitivityEffectDurationHours: 12
  }
};

/**
 * Body weight factors for alcohol metabolism
 * Based on Widmark formula: BAC = (alcohol_grams) / (weight_kg * r)
 * where r is distribution ratio (0.68 for men, 0.55 for women)
 */
export const BODY_DISTRIBUTION_FACTOR = 0.6; // Average for mixed/unknown sex

/**
 * Adjust elimination rate based on body weight
 * Larger bodies metabolize slightly faster (more liver mass)
 *
 * @param baseRate - Base elimination rate in g/hour
 * @param bodyWeightKg - Body weight in kg
 * @returns Adjusted elimination rate
 */
export function adjustEliminationRate(baseRate: number, bodyWeightKg: number): number {
  // Reference weight is 70kg
  const weightFactor = Math.pow(bodyWeightKg / 70, 0.25); // Weak scaling
  return baseRate * weightFactor;
}

/**
 * Calculate blood alcohol level from drinks
 * Uses simplified Widmark formula with time decay
 *
 * @param alcoholGrams - Total alcohol in grams
 * @param bodyWeightKg - Body weight in kg
 * @param minutesSinceDrink - Time since drinking
 * @param drinkType - Type of alcoholic drink
 * @returns Blood alcohol level approximation (g/L)
 */
export function calculateBAL(
  alcoholGrams: number,
  bodyWeightKg: number,
  minutesSinceDrink: number,
  drinkType: AlcoholType
): number {
  const params = ALCOHOL_PARAMS[drinkType];
  const eliminationRate = adjustEliminationRate(params.eliminationRateGramsPerHour, bodyWeightKg);

  // Absorption phase (rising BAL)
  const absorptionFraction = 1 - Math.exp(-minutesSinceDrink / params.absorptionHalfLifeMinutes);
  const absorbedGrams = alcoholGrams * absorptionFraction;

  // Elimination (linear at ~constant rate)
  const hoursElapsed = minutesSinceDrink / 60;
  const eliminatedGrams = Math.min(absorbedGrams, eliminationRate * hoursElapsed);

  // Current alcohol in system
  const currentGrams = absorbedGrams - eliminatedGrams;

  // Convert to BAL (g/L) using Widmark formula
  // BAC = grams / (weight * distribution factor * 10)
  // Multiply by 10 to get g/L instead of g/dL
  const bal = (currentGrams / (bodyWeightKg * BODY_DISTRIBUTION_FACTOR)) * 10;

  return Math.max(0, bal);
}

/**
 * Calculate alcohol state at a given time
 *
 * @param minutesSinceDrink - Minutes since drink was consumed
 * @param alcoholUnits - Number of standard drink units
 * @param drinkType - Type of drink
 * @param bodyWeightKg - Body weight in kg (default 70)
 * @returns Object with current state
 */
export function calculateAlcoholState(
  minutesSinceDrink: number,
  alcoholUnits: number,
  drinkType: AlcoholType,
  bodyWeightKg: number = 70
): {
  absorbing: number;
  inSystem: number;
  eliminated: number;
  bal: number;
  sensitivityModifier: number;
} {
  const alcoholGrams = alcoholUnits * STANDARD_DRINK_GRAMS;
  const params = ALCOHOL_PARAMS[drinkType];
  const eliminationRate = adjustEliminationRate(params.eliminationRateGramsPerHour, bodyWeightKg);

  // Absorption
  const absorptionFraction = 1 - Math.exp(-minutesSinceDrink / params.absorptionHalfLifeMinutes);
  const absorbedGrams = alcoholGrams * absorptionFraction;
  const absorbing = alcoholGrams - absorbedGrams;

  // Elimination
  const hoursElapsed = minutesSinceDrink / 60;
  const eliminatedGrams = Math.min(absorbedGrams, eliminationRate * hoursElapsed);
  const inSystem = Math.max(0, absorbedGrams - eliminatedGrams);

  // BAL
  const bal = (inSystem / (bodyWeightKg * BODY_DISTRIBUTION_FACTOR)) * 10;

  // Insulin sensitivity effect
  // Effect persists for hours after drinking, even after alcohol clears
  const sensitivityDurationMinutes = params.sensitivityEffectDurationHours * 60;
  let sensitivityModifier = 1.0;

  if (minutesSinceDrink < sensitivityDurationMinutes) {
    // Effect ramps up quickly, then decays slowly
    const effectPeak = 60; // Peak effect at 1 hour
    if (minutesSinceDrink < effectPeak) {
      // Ramp up
      const rampFraction = minutesSinceDrink / effectPeak;
      sensitivityModifier = 1 - (1 - params.insulinSensitivityModifier) * rampFraction;
    } else {
      // Decay phase
      const decayTime = minutesSinceDrink - effectPeak;
      const decayDuration = sensitivityDurationMinutes - effectPeak;
      const decayFraction = decayTime / decayDuration;
      sensitivityModifier =
        params.insulinSensitivityModifier + (1 - params.insulinSensitivityModifier) * decayFraction;
    }
  }

  return {
    absorbing: Math.max(0, absorbing),
    inSystem,
    eliminated: eliminatedGrams,
    bal: Math.max(0, bal),
    sensitivityModifier
  };
}

/**
 * Calculate blood alcohol and insulin sensitivity from drink events
 *
 * @param mealEvents - Meal events (alcohol is tracked in meal metadata)
 * @param atTime - Time to calculate at
 * @param bodyWeightKg - User's body weight
 * @returns Blood alcohol result
 */
export function calculateBloodAlcohol(
  mealEvents: PhysiologicalEvent[],
  atTime: Date = new Date(),
  bodyWeightKg: number = 70
): BloodAlcoholResult {
  const drinkContributions: DrinkContribution[] = [];
  let totalAbsorbing = 0;
  let totalInSystem = 0;
  let combinedSensitivityModifier = 1.0;
  let latestSoberTime: Date | null = null;

  // Find events with alcohol
  const alcoholEvents = mealEvents.filter((event) => {
    if (event.eventType !== 'meal') return false;
    const metadata = event.metadata as MealMetadata | undefined;
    return metadata?.alcoholUnits && metadata.alcoholUnits > 0;
  });

  for (const event of alcoholEvents) {
    const metadata = event.metadata as MealMetadata;
    const alcoholUnits = metadata.alcoholUnits || 0;
    const drinkType = (metadata.alcoholType as AlcoholType) || 'mixed';

    const drinkTime = new Date(event.timestamp);
    const minutesSinceDrink = (atTime.getTime() - drinkTime.getTime()) / (1000 * 60);

    // Skip future drinks
    if (minutesSinceDrink < 0) continue;

    const params = ALCOHOL_PARAMS[drinkType];
    const eliminationRate = adjustEliminationRate(params.eliminationRateGramsPerHour, bodyWeightKg);
    const alcoholGrams = alcoholUnits * STANDARD_DRINK_GRAMS;

    // Check if alcohol is fully cleared (and sensitivity effect ended)
    const timeToSober = (alcoholGrams / eliminationRate) * 60; // minutes
    const sensitivityDuration = params.sensitivityEffectDurationHours * 60;
    const totalEffectDuration = Math.max(timeToSober, sensitivityDuration);

    if (minutesSinceDrink >= totalEffectDuration) continue;

    const state = calculateAlcoholState(minutesSinceDrink, alcoholUnits, drinkType, bodyWeightKg);

    totalAbsorbing += state.absorbing;
    totalInSystem += state.inSystem;

    // Combine sensitivity modifiers (multiplicative for multiple drinks)
    combinedSensitivityModifier *= state.sensitivityModifier;

    // Calculate sober time
    const remainingMinutes = Math.max(0, totalEffectDuration - minutesSinceDrink);
    const soberTime = new Date(atTime.getTime() + remainingMinutes * 60 * 1000);
    if (!latestSoberTime || soberTime > latestSoberTime) {
      latestSoberTime = soberTime;
    }

    drinkContributions.push({
      eventId: event.id,
      timestamp: drinkTime,
      alcoholUnits,
      alcoholGrams,
      drinkType,
      remainingGrams: state.inSystem,
      minutesSinceDrink
    });
  }

  // Calculate overall BAL
  const bloodAlcoholLevel = (totalInSystem / (bodyWeightKg * BODY_DISTRIBUTION_FACTOR)) * 10;

  return {
    bloodAlcoholLevel: Math.max(0, bloodAlcoholLevel),
    alcoholAbsorbing: totalAbsorbing,
    alcoholInSystem: totalInSystem,
    insulinSensitivityModifier: combinedSensitivityModifier,
    estimatedSoberTime: latestSoberTime,
    drinkContributions
  };
}

/**
 * Estimate time until sober
 *
 * @param totalAlcoholGrams - Total alcohol in system
 * @param bodyWeightKg - Body weight
 * @returns Minutes until BAL < 0.01
 */
export function estimateTimeUntilSober(totalAlcoholGrams: number, bodyWeightKg: number): number {
  const eliminationRate = adjustEliminationRate(8, bodyWeightKg); // Average rate
  return (totalAlcoholGrams / eliminationRate) * 60;
}

/**
 * Get hypoglycemia risk window after drinking
 * Alcohol can cause delayed hypoglycemia 6-12 hours after drinking
 *
 * @param drinkTime - When drinking occurred
 * @param alcoholUnits - How many drinks
 * @returns Risk window with severity
 */
export function getHypoglycemiaRiskWindow(
  drinkTime: Date,
  alcoholUnits: number
): {
  riskStartTime: Date;
  riskEndTime: Date;
  severity: 'low' | 'medium' | 'high';
  recommendation: string;
} {
  // Risk window is typically 6-12 hours after drinking
  const riskStartMs = drinkTime.getTime() + 6 * 60 * 60 * 1000;
  const riskEndMs = drinkTime.getTime() + 12 * 60 * 60 * 1000;

  let severity: 'low' | 'medium' | 'high';
  let recommendation: string;

  if (alcoholUnits <= 2) {
    severity = 'low';
    recommendation = 'Monitor BSL before bed. Have a snack if below 7 mmol/L.';
  } else if (alcoholUnits <= 4) {
    severity = 'medium';
    recommendation =
      'Check BSL more frequently. Reduce overnight basal if possible. Have carbs available.';
  } else {
    severity = 'high';
    recommendation =
      'High hypo risk. Reduce insulin doses. Check BSL every 2-3 hours. Do not skip meals.';
  }

  return {
    riskStartTime: new Date(riskStartMs),
    riskEndTime: new Date(riskEndMs),
    severity,
    recommendation
  };
}

/**
 * Project alcohol metabolism over time for charting
 *
 * @param mealEvents - Meal events with alcohol
 * @param startTime - Start of projection
 * @param endTime - End of projection
 * @param bodyWeightKg - Body weight
 * @param resolutionMinutes - Time step
 * @returns Array of blood alcohol values over time
 */
export function projectAlcoholMetabolism(
  mealEvents: PhysiologicalEvent[],
  startTime: Date,
  endTime: Date,
  bodyWeightKg: number = 70,
  resolutionMinutes: number = 5
): Array<{ timestamp: Date; bal: number; sensitivityModifier: number; inSystem: number }> {
  const projections: Array<{
    timestamp: Date;
    bal: number;
    sensitivityModifier: number;
    inSystem: number;
  }> = [];
  const stepMs = resolutionMinutes * 60 * 1000;

  for (let t = startTime.getTime(); t <= endTime.getTime(); t += stepMs) {
    const atTime = new Date(t);
    const result = calculateBloodAlcohol(mealEvents, atTime, bodyWeightKg);
    projections.push({
      timestamp: atTime,
      bal: result.bloodAlcoholLevel,
      sensitivityModifier: result.insulinSensitivityModifier,
      inSystem: result.alcoholInSystem
    });
  }

  return projections;
}
