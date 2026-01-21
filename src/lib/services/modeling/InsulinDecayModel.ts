/**
 * Insulin Decay Model
 *
 * Models the pharmacokinetics of insulin absorption and activity over time.
 * Uses exponential decay curves calibrated to insulin type (bolus vs basal).
 *
 * References:
 * - Rapid-acting insulin: onset 15min, peak 1-2hr, duration 3-5hr
 * - Long-acting insulin: onset 1-2hr, no peak, duration 20-24hr
 */

import type { InsulinType, PhysiologicalEvent } from '../../types/events';
import type {
  InsulinKinetics,
  InsulinActivityPoint,
  ActiveInsulinResult,
  DoseContribution
} from '../../types/modeling';

/**
 * Pharmacokinetic parameters for different insulin types
 */
export const INSULIN_KINETICS: Record<InsulinType, InsulinKinetics> = {
  bolus: {
    onsetMinutes: 15,
    peakMinutes: 75, // 1-2 hours, using 1.25hr as midpoint
    durationMinutes: 240, // 4 hours
    halfLifeMinutes: 55 // Calibrated for ~95% absorbed by 4 hours
  },
  basal: {
    onsetMinutes: 90, // 1.5 hours
    peakMinutes: 360, // 6 hours (relatively flat profile)
    durationMinutes: 1440, // 24 hours
    halfLifeMinutes: 300 // 5 hours, gives extended tail
  }
};

/**
 * Calculate insulin activity curve using a modified exponential model
 * Based on Scheiner's "Think Like a Pancreas" insulin action curves
 *
 * @param minutesFromDose - Minutes since insulin was administered
 * @param insulinType - Type of insulin (bolus or basal)
 * @returns Activity point with level and IOB
 */
export function calculateInsulinActivity(
  minutesFromDose: number,
  insulinType: InsulinType
): InsulinActivityPoint {
  const kinetics = INSULIN_KINETICS[insulinType];

  if (minutesFromDose < 0) {
    return { minutesFromDose, activityLevel: 0, insulinOnBoard: 1 };
  }

  if (minutesFromDose >= kinetics.durationMinutes) {
    return { minutesFromDose, activityLevel: 0, insulinOnBoard: 0 };
  }

  // Use a biexponential model for more realistic insulin curves
  // Activity = A * (e^(-t/τ1) - e^(-t/τ2))
  // This creates a curve that rises from 0, peaks, then decays

  const τ1 = kinetics.halfLifeMinutes * 1.4; // Slower decay constant
  const τ2 = kinetics.onsetMinutes * 0.7; // Faster onset constant

  // Calculate activity level (normalized)
  const exp1 = Math.exp(-minutesFromDose / τ1);
  const exp2 = Math.exp(-minutesFromDose / τ2);
  let activityLevel = exp1 - exp2;

  // Find peak activity for normalization
  const tPeak = (τ1 * τ2 * Math.log(τ1 / τ2)) / (τ1 - τ2);
  const peakActivity = Math.exp(-tPeak / τ1) - Math.exp(-tPeak / τ2);

  // Normalize so peak = 1
  activityLevel = activityLevel / peakActivity;

  // Clamp to valid range
  activityLevel = Math.max(0, Math.min(1, activityLevel));

  // Calculate IOB using integral of remaining activity
  // IOB = ∫[t,∞] activity(s) ds / ∫[0,∞] activity(s) ds
  // For biexponential: IOB ≈ (τ1*exp1 - τ2*exp2) / (τ1 - τ2) normalized

  const totalArea = τ1 - τ2;
  const remainingArea = τ1 * exp1 - τ2 * exp2;
  let insulinOnBoard = remainingArea / totalArea;

  // Clamp to valid range
  insulinOnBoard = Math.max(0, Math.min(1, insulinOnBoard));

  return { minutesFromDose, activityLevel, insulinOnBoard };
}

/**
 * Generate full activity curve for visualization
 *
 * @param insulinType - Type of insulin
 * @param resolutionMinutes - Time resolution for curve points
 * @returns Array of activity points
 */
export function generateActivityCurve(
  insulinType: InsulinType,
  resolutionMinutes: number = 5
): InsulinActivityPoint[] {
  const kinetics = INSULIN_KINETICS[insulinType];
  const points: InsulinActivityPoint[] = [];

  for (let t = 0; t <= kinetics.durationMinutes; t += resolutionMinutes) {
    points.push(calculateInsulinActivity(t, insulinType));
  }

  return points;
}

/**
 * Calculate active insulin from multiple doses
 *
 * @param insulinEvents - Array of insulin events
 * @param atTime - Time to calculate IOB at
 * @returns Active insulin result with total IOB and breakdown
 */
export function calculateActiveInsulin(
  insulinEvents: PhysiologicalEvent[],
  atTime: Date = new Date()
): ActiveInsulinResult {
  const doseContributions: DoseContribution[] = [];
  let totalIOB = 0;
  let totalActivityRate = 0;
  let latestClearTime = atTime;

  for (const event of insulinEvents) {
    if (event.eventType !== 'insulin') continue;

    const insulinType = (event.metadata?.type as InsulinType) || 'bolus';
    const units = event.value;
    const doseTime = new Date(event.timestamp);
    const minutesSinceDose = (atTime.getTime() - doseTime.getTime()) / (1000 * 60);

    // Skip future doses
    if (minutesSinceDose < 0) continue;

    const kinetics = INSULIN_KINETICS[insulinType];

    // Skip if dose is past its duration
    if (minutesSinceDose >= kinetics.durationMinutes) continue;

    const activity = calculateInsulinActivity(minutesSinceDose, insulinType);
    const remainingIOB = units * activity.insulinOnBoard;
    const activityLevel = activity.activityLevel;

    // Activity rate in units per hour (activity level is normalized 0-1)
    // At peak, roughly 50% of dose is absorbed per hour for bolus
    const peakAbsorptionRate = units / (kinetics.durationMinutes / 60);
    const currentActivityRate = activityLevel * peakAbsorptionRate * 2;

    totalIOB += remainingIOB;
    totalActivityRate += currentActivityRate;

    // Calculate when this dose will clear
    const remainingMinutes = kinetics.durationMinutes - minutesSinceDose;
    const clearTime = new Date(atTime.getTime() + remainingMinutes * 60 * 1000);
    if (clearTime > latestClearTime) {
      latestClearTime = clearTime;
    }

    doseContributions.push({
      doseId: event.id,
      timestamp: doseTime,
      originalUnits: units,
      insulinType,
      remainingIOB,
      activityLevel,
      minutesSinceDose
    });
  }

  return {
    totalIOB,
    activityRate: totalActivityRate,
    doseContributions,
    estimatedClearTime: latestClearTime
  };
}

/**
 * Estimate BSL impact from active insulin
 *
 * @param iob - Insulin on board in units
 * @param correctionFactor - BSL drop per unit (mmol/L per unit)
 * @returns Expected BSL drop in mmol/L
 */
export function estimateInsulinBSLEffect(iob: number, correctionFactor: number): number {
  return iob * correctionFactor;
}

/**
 * Calculate compound insulin effect when stacking doses
 * Returns a warning level if IOB is high before a new dose
 *
 * @param currentIOB - Current insulin on board
 * @param proposedDose - New dose being considered
 * @param correctionFactor - User's correction factor
 * @returns Warning info about stacking
 */
export function assessInsulinStacking(
  currentIOB: number,
  proposedDose: number,
  correctionFactor: number
): {
  totalIOB: number;
  estimatedBSLDrop: number;
  riskLevel: 'low' | 'medium' | 'high';
  warning?: string;
} {
  const totalIOB = currentIOB + proposedDose;
  const estimatedBSLDrop = totalIOB * correctionFactor;

  let riskLevel: 'low' | 'medium' | 'high' = 'low';
  let warning: string | undefined;

  // Risk thresholds based on potential BSL drop
  if (estimatedBSLDrop > 8) {
    riskLevel = 'high';
    warning = `High IOB stacking: ${totalIOB.toFixed(1)}u could drop BSL by ${estimatedBSLDrop.toFixed(1)} mmol/L`;
  } else if (estimatedBSLDrop > 5) {
    riskLevel = 'medium';
    warning = `Moderate IOB: ${totalIOB.toFixed(1)}u active, expected ${estimatedBSLDrop.toFixed(1)} mmol/L drop`;
  }

  return { totalIOB, estimatedBSLDrop, riskLevel, warning };
}

/**
 * Project insulin activity over time for charting
 *
 * @param insulinEvents - Insulin events to model
 * @param startTime - Start of projection
 * @param endTime - End of projection
 * @param resolutionMinutes - Time step in minutes
 * @returns Array of IOB values over time
 */
export function projectInsulinActivity(
  insulinEvents: PhysiologicalEvent[],
  startTime: Date,
  endTime: Date,
  resolutionMinutes: number = 5
): Array<{ timestamp: Date; iob: number; activityRate: number }> {
  const projections: Array<{ timestamp: Date; iob: number; activityRate: number }> = [];
  const stepMs = resolutionMinutes * 60 * 1000;

  for (let t = startTime.getTime(); t <= endTime.getTime(); t += stepMs) {
    const atTime = new Date(t);
    const result = calculateActiveInsulin(insulinEvents, atTime);
    projections.push({
      timestamp: atTime,
      iob: result.totalIOB,
      activityRate: result.activityRate
    });
  }

  return projections;
}
