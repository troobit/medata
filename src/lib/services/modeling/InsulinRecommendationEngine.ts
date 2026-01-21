/**
 * Insulin Dose Recommendation Engine
 *
 * Calculates recommended insulin doses based on:
 * - Carbohydrate intake (using insulin-to-carb ratio)
 * - Current BSL and correction factor
 * - Insulin on board (IOB)
 * - Carbs on board (COB)
 * - Alcohol effects
 * - Time of day sensitivity
 *
 * Provides confidence intervals based on parameter uncertainty
 * and includes safety warnings for stacking, hypo risk, etc.
 *
 * IMPORTANT: This is a decision-support tool, not medical advice.
 * Users must verify all recommendations with their healthcare provider.
 */

import type { PhysiologicalEvent } from '../../types/events';
import type {
  InsulinRecommendation,
  DoseBreakdown,
  UserModelParameters,
  EventWindow
} from '../../types/modeling';

import { calculateActiveInsulin, assessInsulinStacking } from './InsulinDecayModel';
import { calculateActiveCarbs } from './CarbAbsorptionModel';
import { calculateBloodAlcohol, getHypoglycemiaRiskWindow } from './AlcoholMetabolismModel';
import { adjustDoseForTimeOfDay } from './CircadianModel';
import { buildEventWindow, DEFAULT_USER_PARAMETERS } from './BSLPredictionModel';

/**
 * Safety thresholds for recommendations
 */
const SAFETY_LIMITS = {
  maxSingleDose: 30, // Maximum units in one dose
  maxTotalIOB: 40, // Maximum total IOB
  minBSLForCorrection: 7.0, // Don't correct below this BSL
  hypoRiskBSL: 5.0, // Extra caution below this
  severeHypoRisk: 4.0, // Do not recommend insulin below this
  maxCorrectionDose: 10, // Cap on correction dose
  minConfidenceThreshold: 0.4 // Minimum confidence to show recommendation
};

/**
 * Confidence factors for recommendation uncertainty
 */
const CONFIDENCE_FACTORS = {
  parameterUncertainty: 0.15, // 15% uncertainty in user parameters
  iobUncertainty: 0.2, // 20% uncertainty in IOB calculation
  cobUncertainty: 0.25, // 25% uncertainty in COB
  alcoholUncertainty: 0.3 // 30% additional uncertainty with alcohol
};

/**
 * Calculate recommended insulin dose for a meal
 *
 * @param carbsGrams - Carbohydrates being consumed
 * @param currentBSL - Current blood sugar level (mmol/L)
 * @param events - Event window with recent insulin/meal/BSL events
 * @param userParams - User-specific parameters
 * @returns Insulin recommendation with confidence interval
 */
export function calculateMealDose(
  carbsGrams: number,
  currentBSL: number | null,
  events: EventWindow,
  userParams: UserModelParameters = DEFAULT_USER_PARAMETERS
): InsulinRecommendation {
  const warnings: string[] = [];
  const now = new Date();

  // Calculate current metabolic state
  const iobResult = calculateActiveInsulin(events.insulinEvents, now);
  const cobResult = calculateActiveCarbs(events.mealEvents, now);
  const alcoholResult = calculateBloodAlcohol(events.mealEvents, now, userParams.bodyWeightKg);

  // 1. Carb coverage dose
  const carbCoverage = carbsGrams / userParams.insulinToCarbRatio;

  // 2. Correction dose (if BSL known and above threshold)
  let correctionDose = 0;
  if (currentBSL !== null && currentBSL > SAFETY_LIMITS.minBSLForCorrection) {
    const bslAboveTarget = currentBSL - userParams.targetBSL;
    correctionDose = bslAboveTarget / userParams.correctionFactor;
    correctionDose = Math.min(correctionDose, SAFETY_LIMITS.maxCorrectionDose);
    correctionDose = Math.max(0, correctionDose);
  }

  // 3. IOB adjustment (subtract active insulin)
  const iobAdjustment = -iobResult.totalIOB;
  if (iobResult.totalIOB > 2) {
    warnings.push(
      `${iobResult.totalIOB.toFixed(1)} units of insulin still active from previous doses`
    );
  }

  // 4. COB adjustment (some carbs still absorbing)
  // If there are significant COB, the new carbs add to the queue
  // Generally we don't reduce dose for COB, but we warn about stacking
  let cobAdjustment = 0;
  if (cobResult.totalCOB > 20) {
    warnings.push(
      `${cobResult.totalCOB.toFixed(0)}g carbs still being absorbed from previous meals`
    );
    // Small reduction if lots of carbs on board and low BSL
    if (currentBSL !== null && currentBSL < 6.0) {
      cobAdjustment = -cobResult.totalCOB / userParams.insulinToCarbRatio * 0.25;
    }
  }

  // 5. Alcohol adjustment
  let alcoholAdjustment = 0;
  if (alcoholResult.alcoholInSystem > 0) {
    // Reduce dose due to increased insulin sensitivity
    const sensitivityFactor = alcoholResult.insulinSensitivityModifier;
    alcoholAdjustment = -(carbCoverage + correctionDose) * (1 - sensitivityFactor);

    warnings.push(
      `Alcohol detected: increased insulin sensitivity. Dose reduced by ${Math.round((1 - sensitivityFactor) * 100)}%`
    );

    // Add hypo risk warning
    const latestDrink = alcoholResult.drinkContributions[0];
    if (latestDrink) {
      const risk = getHypoglycemiaRiskWindow(latestDrink.timestamp, latestDrink.alcoholUnits);
      if (risk.severity !== 'low') {
        warnings.push(risk.recommendation);
      }
    }
  }

  // 6. Time-of-day adjustment
  const timeAdjust = adjustDoseForTimeOfDay(
    carbCoverage + correctionDose,
    now,
    userParams.circadianAdjustments
  );
  const circadianAdjustment =
    timeAdjust.adjustedDose - (carbCoverage + correctionDose);

  // Calculate total dose
  let recommendedDose =
    carbCoverage +
    correctionDose +
    iobAdjustment +
    cobAdjustment +
    alcoholAdjustment +
    circadianAdjustment;

  // Safety checks
  if (currentBSL !== null && currentBSL < SAFETY_LIMITS.severeHypoRisk) {
    recommendedDose = 0;
    warnings.unshift('⚠️ BSL is critically low. Do not take insulin. Treat hypo first.');
  } else if (currentBSL !== null && currentBSL < SAFETY_LIMITS.hypoRiskBSL) {
    recommendedDose = Math.min(recommendedDose, carbCoverage * 0.5);
    warnings.unshift('⚠️ BSL is low. Reduced dose recommended. Consider eating before dosing.');
  }

  // Check stacking risk
  const stackingRisk = assessInsulinStacking(
    iobResult.totalIOB,
    recommendedDose,
    userParams.correctionFactor
  );
  if (stackingRisk.riskLevel === 'high') {
    warnings.push(stackingRisk.warning!);
    recommendedDose = Math.min(recommendedDose, carbCoverage);
  } else if (stackingRisk.riskLevel === 'medium' && stackingRisk.warning) {
    warnings.push(stackingRisk.warning);
  }

  // Apply safety limits
  recommendedDose = Math.max(0, recommendedDose);
  recommendedDose = Math.min(recommendedDose, SAFETY_LIMITS.maxSingleDose);

  // Round to nearest 0.5 units (most pumps/pens)
  recommendedDose = Math.round(recommendedDose * 2) / 2;

  // Calculate confidence interval
  const { lower, upper, confidence } = calculateDoseConfidence(
    recommendedDose,
    alcoholResult.alcoholInSystem > 0,
    currentBSL === null,
    carbsGrams
  );

  const breakdown: DoseBreakdown = {
    carbCoverage,
    correctionDose,
    iobAdjustment,
    cobAdjustment,
    alcoholAdjustment,
    circadianAdjustment
  };

  return {
    recommendedDose,
    confidenceInterval: [lower, upper],
    confidence,
    breakdown,
    warnings,
    timestamp: now
  };
}

/**
 * Calculate correction dose only (no carbs)
 *
 * @param currentBSL - Current BSL in mmol/L
 * @param events - Event window
 * @param userParams - User parameters
 * @returns Insulin recommendation for correction only
 */
export function calculateCorrectionDose(
  currentBSL: number,
  events: EventWindow,
  userParams: UserModelParameters = DEFAULT_USER_PARAMETERS
): InsulinRecommendation {
  return calculateMealDose(0, currentBSL, events, userParams);
}

/**
 * Calculate confidence interval for dose recommendation
 */
function calculateDoseConfidence(
  baseDose: number,
  hasAlcohol: boolean,
  noBSL: boolean,
  carbsGrams: number
): { lower: number; upper: number; confidence: number } {
  // Base uncertainty from parameter estimates
  let uncertainty = baseDose * CONFIDENCE_FACTORS.parameterUncertainty;

  // Add uncertainty for IOB estimation
  uncertainty += baseDose * CONFIDENCE_FACTORS.iobUncertainty;

  // Add uncertainty if alcohol present
  if (hasAlcohol) {
    uncertainty += baseDose * CONFIDENCE_FACTORS.alcoholUncertainty;
  }

  // Add uncertainty if no BSL reading
  if (noBSL) {
    uncertainty += 1.0; // Flat 1 unit uncertainty without BSL
  }

  // More carbs = more uncertainty
  if (carbsGrams > 60) {
    uncertainty += (carbsGrams - 60) / 100;
  }

  // Calculate bounds (minimum 0)
  const lower = Math.max(0, Math.round((baseDose - uncertainty) * 2) / 2);
  const upper = Math.round((baseDose + uncertainty) * 2) / 2;

  // Confidence level (inversely proportional to relative uncertainty)
  let confidence = baseDose > 0 ? 1 - uncertainty / baseDose : 0.5;
  confidence = Math.max(0.3, Math.min(0.95, confidence));

  return { lower, upper, confidence };
}

/**
 * Get recommendation for pre-meal insulin timing
 *
 * @param currentBSL - Current BSL
 * @param plannedCarbs - Planned carb intake
 * @returns Timing recommendation
 */
export function getTimingRecommendation(
  currentBSL: number | null,
  plannedCarbs: number
): {
  minutesBefore: number;
  reason: string;
} {
  if (currentBSL === null) {
    return {
      minutesBefore: 0,
      reason: 'Without knowing current BSL, inject when you start eating'
    };
  }

  if (currentBSL < 4.0) {
    return {
      minutesBefore: -15, // After eating
      reason: 'BSL is low. Eat first, then dose if needed after 15 minutes'
    };
  }

  if (currentBSL < 5.0) {
    return {
      minutesBefore: 0,
      reason: 'BSL is on the low side. Inject as you start eating'
    };
  }

  if (currentBSL < 7.0) {
    return {
      minutesBefore: 10,
      reason: 'Normal BSL. Inject 10 minutes before eating for optimal timing'
    };
  }

  if (currentBSL < 10.0) {
    return {
      minutesBefore: 15,
      reason: 'BSL is elevated. Inject 15 minutes before eating'
    };
  }

  return {
    minutesBefore: 20,
    reason: 'BSL is high. Consider injecting 20 minutes before eating'
  };
}

/**
 * Suggest insulin-to-carb ratio based on historical data
 * Analyzes past meal/insulin/BSL patterns to estimate ICR
 *
 * @param events - Historical events
 * @param currentICR - Current ICR setting
 * @returns Suggested ICR with confidence
 */
export function suggestICRAdjustment(
  events: PhysiologicalEvent[],
  currentICR: number
): {
  suggestedICR: number;
  confidence: number;
  analysis: string;
  dataPoints: number;
} {
  // Find meal-insulin pairs where we have BSL before and 2-4 hours after
  const mealEvents = events.filter((e) => e.eventType === 'meal');
  const insulinEvents = events.filter((e) => e.eventType === 'insulin');
  const bslEvents = events.filter((e) => e.eventType === 'bsl');

  const successfulPairs: Array<{ carbs: number; insulin: number; outcome: 'good' | 'high' | 'low' }> =
    [];

  for (const meal of mealEvents) {
    const mealTime = new Date(meal.timestamp).getTime();
    const mealCarbs = (meal.metadata as { carbs?: number })?.carbs || meal.value;

    if (!mealCarbs || mealCarbs < 10) continue;

    // Find insulin within 30 minutes of meal
    const nearbyInsulin = insulinEvents.find((i) => {
      const iTime = new Date(i.timestamp).getTime();
      return Math.abs(iTime - mealTime) < 30 * 60 * 1000;
    });

    if (!nearbyInsulin || nearbyInsulin.value < 1) continue;

    // Find BSL 2-4 hours after meal
    const postMealBSL = bslEvents.find((b) => {
      const bTime = new Date(b.timestamp).getTime();
      const hoursAfter = (bTime - mealTime) / (1000 * 60 * 60);
      return hoursAfter >= 2 && hoursAfter <= 4;
    });

    if (!postMealBSL) continue;

    // Categorize outcome
    let outcome: 'good' | 'high' | 'low';
    if (postMealBSL.value < 4.5) outcome = 'low';
    else if (postMealBSL.value > 9.0) outcome = 'high';
    else outcome = 'good';

    successfulPairs.push({
      carbs: mealCarbs,
      insulin: nearbyInsulin.value,
      outcome
    });
  }

  if (successfulPairs.length < 5) {
    return {
      suggestedICR: currentICR,
      confidence: 0,
      analysis: 'Insufficient data for ICR analysis. Need at least 5 meal-insulin pairs with post-meal BSL.',
      dataPoints: successfulPairs.length
    };
  }

  // Calculate average ICR from successful pairs
  const goodOutcomes = successfulPairs.filter((p) => p.outcome === 'good');
  const highOutcomes = successfulPairs.filter((p) => p.outcome === 'high');
  const lowOutcomes = successfulPairs.filter((p) => p.outcome === 'low');

  let suggestedICR = currentICR;
  let analysis = '';

  if (highOutcomes.length > successfulPairs.length * 0.4) {
    // Frequently going high - need more insulin (lower ICR)
    suggestedICR = currentICR * 0.9;
    analysis = `${Math.round((highOutcomes.length / successfulPairs.length) * 100)}% of meals result in high BSL. Consider lowering ICR from ${currentICR} to ${suggestedICR.toFixed(1)}.`;
  } else if (lowOutcomes.length > successfulPairs.length * 0.2) {
    // Going low - need less insulin (higher ICR)
    suggestedICR = currentICR * 1.15;
    analysis = `${Math.round((lowOutcomes.length / successfulPairs.length) * 100)}% of meals result in low BSL. Consider raising ICR from ${currentICR} to ${suggestedICR.toFixed(1)}.`;
  } else if (goodOutcomes.length > successfulPairs.length * 0.6) {
    analysis = `Current ICR of ${currentICR} is working well. ${Math.round((goodOutcomes.length / successfulPairs.length) * 100)}% of meals in target range.`;
  } else {
    analysis = `Mixed results. High: ${highOutcomes.length}, Good: ${goodOutcomes.length}, Low: ${lowOutcomes.length}. May need to review meal logging accuracy.`;
  }

  const confidence = Math.min(0.9, successfulPairs.length / 20);

  return {
    suggestedICR: Math.round(suggestedICR * 10) / 10,
    confidence,
    analysis,
    dataPoints: successfulPairs.length
  };
}

/**
 * Create a recommendation explanation for display
 *
 * @param recommendation - The insulin recommendation
 * @returns Human-readable explanation
 */
export function explainRecommendation(recommendation: InsulinRecommendation): string {
  const { breakdown, recommendedDose, confidence, confidenceInterval } = recommendation;
  const lines: string[] = [];

  lines.push(`Recommended dose: ${recommendedDose} units`);
  lines.push(`Confidence: ${Math.round(confidence * 100)}% (${confidenceInterval[0]}-${confidenceInterval[1]} units)`);
  lines.push('');
  lines.push('Breakdown:');

  if (breakdown.carbCoverage > 0) {
    lines.push(`  Carb coverage: +${breakdown.carbCoverage.toFixed(1)} units`);
  }
  if (breakdown.correctionDose > 0) {
    lines.push(`  BSL correction: +${breakdown.correctionDose.toFixed(1)} units`);
  }
  if (breakdown.iobAdjustment < 0) {
    lines.push(`  Active insulin: ${breakdown.iobAdjustment.toFixed(1)} units`);
  }
  if (breakdown.cobAdjustment !== 0) {
    lines.push(`  Active carbs adj: ${breakdown.cobAdjustment.toFixed(1)} units`);
  }
  if (breakdown.alcoholAdjustment !== 0) {
    lines.push(`  Alcohol adj: ${breakdown.alcoholAdjustment.toFixed(1)} units`);
  }
  if (Math.abs(breakdown.circadianAdjustment) > 0.1) {
    lines.push(`  Time-of-day: ${breakdown.circadianAdjustment > 0 ? '+' : ''}${breakdown.circadianAdjustment.toFixed(1)} units`);
  }

  return lines.join('\n');
}
