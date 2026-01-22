/**
 * BSL Prediction Model
 *
 * Combines insulin, carbohydrate, alcohol, and circadian models to predict
 * blood sugar levels over time. Uses physiological events to forecast BSL
 * and generate prediction curves with confidence intervals.
 *
 * The model works by:
 * 1. Starting from a known BSL measurement
 * 2. Adding expected glucose from carbs being absorbed
 * 3. Subtracting expected BSL drop from active insulin
 * 4. Adjusting for alcohol effects on insulin sensitivity
 * 5. Adding circadian drift (dawn phenomenon, etc.)
 *
 * Confidence intervals widen over time due to:
 * - Uncertainty in user parameters (ICR, CF)
 * - Variability in absorption rates
 * - Unmeasured factors (stress, activity, etc.)
 */

import type { PhysiologicalEvent, BSLMetadata } from '../../types/events';
import type {
  BSLPrediction,
  BSLPredictionFactors,
  BSLTimeSeries,
  BSLTimeSeriesPoint,
  MetabolicState,
  UserModelParameters,
  EventWindow
} from '../../types/modeling';

import { calculateActiveInsulin, estimateInsulinBSLEffect } from './InsulinDecayModel';
import { calculateActiveCarbs, estimateCarbBSLEffect } from './CarbAbsorptionModel';
import { calculateBloodAlcohol } from './AlcoholMetabolismModel';
import { interpolateCircadianFactors, estimateCircadianBSLDrift } from './CircadianModel';

/**
 * Default user parameters if not provided
 * These are conservative estimates; users should personalise
 */
export const DEFAULT_USER_PARAMETERS: UserModelParameters = {
  insulinToCarbRatio: 10, // 1 unit covers 10g carbs
  correctionFactor: 2.0, // 1 unit drops BSL by 2 mmol/L
  targetBSL: 6.0, // Target 6 mmol/L
  bodyWeightKg: 70 // Average adult weight
};

/**
 * Confidence interval parameters
 */
const CONFIDENCE_PARAMS = {
  baseUncertainty: 0.5, // Base uncertainty in mmol/L
  timeDecayFactor: 0.02, // Uncertainty grows by this per minute
  maxUncertainty: 5.0, // Cap on uncertainty
  alcoholUncertaintyBoost: 0.3, // Additional uncertainty with alcohol
  noRecentBSLPenalty: 1.0 // Extra uncertainty if no recent BSL
};

/**
 * Calculate metabolic state at a point in time
 *
 * @param events - Event window containing relevant events
 * @param atTime - Time to calculate state for
 * @param userParams - User-specific parameters
 * @returns Metabolic state snapshot
 */
export function calculateMetabolicState(
  events: EventWindow,
  atTime: Date,
  userParams: UserModelParameters = DEFAULT_USER_PARAMETERS
): MetabolicState {
  // Calculate active insulin
  const insulin = calculateActiveInsulin(events.insulinEvents, atTime);

  // Calculate active carbs
  const carbs = calculateActiveCarbs(events.mealEvents, atTime);

  // Calculate alcohol effects
  const alcohol = calculateBloodAlcohol(events.mealEvents, atTime, userParams.bodyWeightKg);

  // Calculate circadian factors
  const circadian = interpolateCircadianFactors(atTime, userParams.circadianAdjustments);

  // Find last known BSL
  let lastBSL: MetabolicState['lastBSL'] | undefined;
  const bslEvents = events.bslEvents
    .filter((e) => new Date(e.timestamp) <= atTime)
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());

  if (bslEvents.length > 0) {
    const latest = bslEvents[0];
    const metadata = latest.metadata as BSLMetadata | undefined;
    lastBSL = {
      value: latest.value,
      timestamp: new Date(latest.timestamp),
      source: metadata?.source || 'manual'
    };
  }

  return {
    timestamp: atTime,
    insulin,
    carbs,
    alcohol,
    circadian,
    lastBSL
  };
}

/**
 * Calculate prediction factors for BSL change
 *
 * @param state - Current metabolic state
 * @param lastBSLTime - Time of last BSL reading
 * @param targetTime - Time to predict for
 * @param userParams - User parameters
 * @returns Breakdown of factors affecting BSL
 */
export function calculatePredictionFactors(
  state: MetabolicState,
  lastBSLTime: Date,
  targetTime: Date,
  userParams: UserModelParameters = DEFAULT_USER_PARAMETERS
): BSLPredictionFactors {
  // Insulin effect: IOB * correction factor = BSL drop
  // Adjusted for alcohol sensitivity
  const insulinDropBase = estimateInsulinBSLEffect(
    state.insulin.totalIOB,
    userParams.correctionFactor
  );
  const insulinEffect = -insulinDropBase * state.alcohol.insulinSensitivityModifier;

  // Carb effect: COB converted to equivalent insulin * CF = BSL rise
  const carbRise = estimateCarbBSLEffect(
    state.carbs.totalCOB,
    userParams.insulinToCarbRatio,
    userParams.correctionFactor
  );
  // Adjusted for time-of-day sensitivity
  const carbEffect = carbRise / state.circadian.combinedFactor;

  // Alcohol direct effect on BSL (tends to lower it)
  // Rough model: alcohol in system can suppress liver glucose output
  const alcoholEffect =
    state.alcohol.alcoholInSystem > 0 ? -state.alcohol.alcoholInSystem * 0.05 : 0;

  // Circadian drift (dawn phenomenon, etc.)
  const circadianAdjustment = estimateCircadianBSLDrift(lastBSLTime, targetTime);

  // Baseline drift (liver glucose output minus basal usage)
  // Small positive drift if no insulin on board
  const baselineDrift = state.insulin.totalIOB < 0.5 ? 0.1 : 0;

  return {
    insulinEffect,
    carbEffect,
    alcoholEffect,
    circadianAdjustment,
    baselineDrift
  };
}

/**
 * Calculate confidence interval for prediction
 *
 * @param minutesFromBaseline - Minutes since last known BSL
 * @param hasAlcohol - Whether alcohol is in system
 * @param hasRecentBSL - Whether we have a recent BSL reading
 * @param confidence - Base confidence level
 * @returns Lower and upper bounds multiplier
 */
function calculateConfidenceInterval(
  minutesFromBaseline: number,
  hasAlcohol: boolean,
  hasRecentBSL: boolean,
  baseValue: number
): { lower: number; upper: number; confidence: number } {
  let uncertainty = CONFIDENCE_PARAMS.baseUncertainty;

  // Increase uncertainty over time
  uncertainty += minutesFromBaseline * CONFIDENCE_PARAMS.timeDecayFactor;

  // Alcohol adds unpredictability
  if (hasAlcohol) {
    uncertainty += CONFIDENCE_PARAMS.alcoholUncertaintyBoost;
  }

  // No recent BSL means we're less confident
  if (!hasRecentBSL) {
    uncertainty += CONFIDENCE_PARAMS.noRecentBSLPenalty;
  }

  // Cap uncertainty
  uncertainty = Math.min(uncertainty, CONFIDENCE_PARAMS.maxUncertainty);

  // Confidence decreases as uncertainty increases
  const confidence = Math.max(0.2, 1 - uncertainty / CONFIDENCE_PARAMS.maxUncertainty);

  return {
    lower: baseValue - uncertainty,
    upper: baseValue + uncertainty,
    confidence
  };
}

/**
 * Predict BSL at a future time
 *
 * @param events - Event window with insulin, meals, BSL
 * @param targetTime - Time to predict BSL for
 * @param userParams - User-specific parameters
 * @returns BSL prediction with confidence interval
 */
export function predictBSL(
  events: EventWindow,
  targetTime: Date,
  userParams: UserModelParameters = DEFAULT_USER_PARAMETERS
): BSLPrediction {
  // Get current metabolic state
  const state = calculateMetabolicState(events, targetTime, userParams);

  // Determine baseline BSL
  const hasRecentBSL = state.lastBSL !== undefined;
  const currentBSL = state.lastBSL?.value ?? userParams.targetBSL;
  const lastBSLTime = state.lastBSL?.timestamp ?? new Date();
  const minutesFromBaseline = (targetTime.getTime() - lastBSLTime.getTime()) / (1000 * 60);

  // Calculate prediction factors
  const factors = calculatePredictionFactors(state, lastBSLTime, targetTime, userParams);

  // Sum all effects
  const totalChange =
    factors.insulinEffect +
    factors.carbEffect +
    factors.alcoholEffect +
    factors.circadianAdjustment +
    factors.baselineDrift;

  const predictedBSL = Math.max(2.0, currentBSL + totalChange); // Floor at 2.0 (severe hypo)

  // Calculate confidence interval
  const hasAlcohol = state.alcohol.alcoholInSystem > 0;
  const { lower, upper, confidence } = calculateConfidenceInterval(
    minutesFromBaseline,
    hasAlcohol,
    hasRecentBSL,
    predictedBSL
  );

  return {
    predictedBSL,
    currentBSL,
    confidenceInterval: [Math.max(2.0, lower), upper],
    confidence,
    factors,
    predictionTime: new Date(),
    targetTime
  };
}

/**
 * Generate BSL time series for charting
 *
 * @param events - Event window
 * @param startTime - Start of prediction window
 * @param endTime - End of prediction window
 * @param userParams - User parameters
 * @param resolutionMinutes - Time step (default 5 minutes)
 * @returns BSL time series with predictions at each point
 */
export function generateBSLTimeSeries(
  events: EventWindow,
  startTime: Date,
  endTime: Date,
  userParams: UserModelParameters = DEFAULT_USER_PARAMETERS,
  resolutionMinutes: number = 5
): BSLTimeSeries {
  const points: BSLTimeSeriesPoint[] = [];
  const stepMs = resolutionMinutes * 60 * 1000;

  for (let t = startTime.getTime(); t <= endTime.getTime(); t += stepMs) {
    const timestamp = new Date(t);
    const prediction = predictBSL(events, timestamp, userParams);
    const state = calculateMetabolicState(events, timestamp, userParams);

    points.push({
      timestamp,
      predictedBSL: prediction.predictedBSL,
      lowerBound: prediction.confidenceInterval[0],
      upperBound: prediction.confidenceInterval[1],
      state
    });
  }

  return {
    points,
    startTime,
    endTime,
    resolutionMinutes
  };
}

/**
 * Build event window from events array
 *
 * @param events - All physiological events
 * @param startTime - Window start
 * @param endTime - Window end
 * @returns Categorised event window
 */
export function buildEventWindow(
  events: PhysiologicalEvent[],
  startTime: Date,
  endTime: Date
): EventWindow {
  // For insulin and meals, look back further (they have lasting effects)
  const insulinLookback = 24 * 60 * 60 * 1000; // 24 hours
  const mealLookback = 6 * 60 * 60 * 1000; // 6 hours
  const bslLookback = 12 * 60 * 60 * 1000; // 12 hours

  const insulinStart = new Date(startTime.getTime() - insulinLookback);
  const mealStart = new Date(startTime.getTime() - mealLookback);
  const bslStart = new Date(startTime.getTime() - bslLookback);

  return {
    insulinEvents: events.filter(
      (e) =>
        e.eventType === 'insulin' &&
        new Date(e.timestamp) >= insulinStart &&
        new Date(e.timestamp) <= endTime
    ),
    mealEvents: events.filter(
      (e) =>
        e.eventType === 'meal' &&
        new Date(e.timestamp) >= mealStart &&
        new Date(e.timestamp) <= endTime
    ),
    bslEvents: events.filter(
      (e) =>
        e.eventType === 'bsl' &&
        new Date(e.timestamp) >= bslStart &&
        new Date(e.timestamp) <= endTime
    ),
    startTime,
    endTime
  };
}

/**
 * Calculate when BSL will reach target
 *
 * @param events - Event window
 * @param targetBSL - Target BSL in mmol/L
 * @param userParams - User parameters
 * @param maxHours - Maximum hours to look ahead
 * @returns Estimated time to reach target, or null if won't reach
 */
export function estimateTimeToTarget(
  events: EventWindow,
  targetBSL: number,
  userParams: UserModelParameters = DEFAULT_USER_PARAMETERS,
  maxHours: number = 6
): { time: Date; predictedBSL: number } | null {
  const now = new Date();
  const maxTime = new Date(now.getTime() + maxHours * 60 * 60 * 1000);
  const stepMs = 5 * 60 * 1000; // 5 minute steps

  const currentPrediction = predictBSL(events, now, userParams);

  // Check if we're already at target
  if (Math.abs(currentPrediction.predictedBSL - targetBSL) < 0.5) {
    return { time: now, predictedBSL: currentPrediction.predictedBSL };
  }

  const goingDown = currentPrediction.predictedBSL > targetBSL;

  for (let t = now.getTime() + stepMs; t <= maxTime.getTime(); t += stepMs) {
    const prediction = predictBSL(events, new Date(t), userParams);

    // Check if we've crossed the target
    if (goingDown && prediction.predictedBSL <= targetBSL) {
      return { time: new Date(t), predictedBSL: prediction.predictedBSL };
    }
    if (!goingDown && prediction.predictedBSL >= targetBSL) {
      return { time: new Date(t), predictedBSL: prediction.predictedBSL };
    }
  }

  return null; // Won't reach target in time window
}

/**
 * Check for predicted hypo/hyper events
 *
 * @param timeSeries - Generated BSL time series
 * @param hypoThreshold - Hypoglycemia threshold (default 4.0 mmol/L)
 * @param hyperThreshold - Hyperglycemia threshold (default 10.0 mmol/L)
 * @returns Array of alert events
 */
export function checkForAlerts(
  timeSeries: BSLTimeSeries,
  hypoThreshold: number = 4.0,
  hyperThreshold: number = 10.0
): Array<{
  type: 'hypo' | 'hyper';
  predictedTime: Date;
  predictedBSL: number;
  confidence: number;
  severity: 'warning' | 'alert' | 'urgent';
}> {
  const alerts: Array<{
    type: 'hypo' | 'hyper';
    predictedTime: Date;
    predictedBSL: number;
    confidence: number;
    severity: 'warning' | 'alert' | 'urgent';
  }> = [];

  for (const point of timeSeries.points) {
    // Check lower bound for hypo (more conservative)
    if (point.lowerBound < hypoThreshold) {
      let severity: 'warning' | 'alert' | 'urgent' = 'warning';
      if (point.predictedBSL < 3.5) severity = 'urgent';
      else if (point.predictedBSL < hypoThreshold) severity = 'alert';

      alerts.push({
        type: 'hypo',
        predictedTime: point.timestamp,
        predictedBSL: point.predictedBSL,
        confidence:
          1 - (point.upperBound - point.lowerBound) / (CONFIDENCE_PARAMS.maxUncertainty * 2),
        severity
      });
    }

    // Check upper bound for hyper
    if (point.upperBound > hyperThreshold) {
      let severity: 'warning' | 'alert' | 'urgent' = 'warning';
      if (point.predictedBSL > 15) severity = 'urgent';
      else if (point.predictedBSL > hyperThreshold) severity = 'alert';

      alerts.push({
        type: 'hyper',
        predictedTime: point.timestamp,
        predictedBSL: point.predictedBSL,
        confidence:
          1 - (point.upperBound - point.lowerBound) / (CONFIDENCE_PARAMS.maxUncertainty * 2),
        severity
      });
    }
  }

  // De-duplicate consecutive alerts of same type
  return alerts.filter(
    (alert, index, arr) =>
      index === 0 ||
      alert.type !== arr[index - 1].type ||
      alert.predictedTime.getTime() - arr[index - 1].predictedTime.getTime() > 30 * 60 * 1000
  );
}
