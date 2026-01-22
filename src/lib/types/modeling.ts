/**
 * Types for regression and modeling (BSL prediction, insulin decay, etc.)
 */

import type { InsulinType, AlcoholType, PhysiologicalEvent } from './events';

/**
 * Insulin pharmacokinetic parameters by type
 */
export interface InsulinKinetics {
  /** Onset of action in minutes */
  onsetMinutes: number;
  /** Peak action time in minutes */
  peakMinutes: number;
  /** Duration of action in minutes */
  durationMinutes: number;
  /** Half-life in minutes (for exponential decay) */
  halfLifeMinutes: number;
}

/**
 * Insulin activity curve point
 */
export interface InsulinActivityPoint {
  /** Time offset from injection in minutes */
  minutesFromDose: number;
  /** Relative activity level (0-1, where 1 is peak) */
  activityLevel: number;
  /** Cumulative insulin on board as fraction of dose (0-1) */
  insulinOnBoard: number;
}

/**
 * Active insulin calculation result
 */
export interface ActiveInsulinResult {
  /** Total insulin on board (IOB) in units */
  totalIOB: number;
  /** Current activity rate (units being absorbed per hour) */
  activityRate: number;
  /** Breakdown by individual dose */
  doseContributions: DoseContribution[];
  /** Time when IOB will be negligible (<0.1 units) */
  estimatedClearTime: Date;
}

/**
 * Contribution from a single insulin dose
 */
export interface DoseContribution {
  /** Original dose ID */
  doseId: string;
  /** Dose timestamp */
  timestamp: Date;
  /** Original dose in units */
  originalUnits: number;
  /** Insulin type */
  insulinType: InsulinType;
  /** Remaining IOB from this dose */
  remainingIOB: number;
  /** Current activity level (0-1) */
  activityLevel: number;
  /** Minutes since dose */
  minutesSinceDose: number;
}

/**
 * Carbohydrate absorption parameters
 */
export interface CarbAbsorptionParams {
  /** Glycemic index (0-100) */
  glycemicIndex: number;
  /** Peak absorption time in minutes */
  peakMinutes: number;
  /** Total absorption duration in minutes */
  durationMinutes: number;
  /** Half-life for exponential decay in minutes */
  halfLifeMinutes: number;
}

/**
 * Carbohydrate absorption curve point
 */
export interface CarbAbsorptionPoint {
  /** Time offset from meal in minutes */
  minutesFromMeal: number;
  /** Absorption rate (grams per hour) */
  absorptionRate: number;
  /** Carbs on board (grams remaining to absorb) */
  carbsOnBoard: number;
  /** Cumulative carbs absorbed */
  carbsAbsorbed: number;
}

/**
 * Active carbs calculation result
 */
export interface ActiveCarbsResult {
  /** Total carbs on board (COB) in grams */
  totalCOB: number;
  /** Current absorption rate (grams per hour) */
  absorptionRate: number;
  /** Breakdown by meal */
  mealContributions: MealContribution[];
  /** Estimated time when all carbs absorbed */
  estimatedAbsorptionComplete: Date;
}

/**
 * Contribution from a single meal
 */
export interface MealContribution {
  /** Original meal event ID */
  mealId: string;
  /** Meal timestamp */
  timestamp: Date;
  /** Original carbs in grams */
  originalCarbs: number;
  /** Remaining COB from this meal */
  remainingCOB: number;
  /** Current absorption rate (g/hr) */
  absorptionRate: number;
  /** Minutes since meal */
  minutesSinceMeal: number;
  /** Glycemic index used */
  glycemicIndex: number;
}

/**
 * Alcohol metabolism parameters by drink type
 */
export interface AlcoholMetabolismParams {
  /** Drink type */
  drinkType: AlcoholType;
  /** Absorption half-life in minutes (faster = quicker to peak) */
  absorptionHalfLifeMinutes: number;
  /** Elimination rate in g/hour (varies by body weight) */
  eliminationRateGramsPerHour: number;
  /** Peak blood alcohol time in minutes */
  peakTimeMinutes: number;
  /** Insulin sensitivity modifier (1.0 = normal, <1.0 = increased sensitivity) */
  insulinSensitivityModifier: number;
  /** Duration of insulin sensitivity effect in hours */
  sensitivityEffectDurationHours: number;
}

/**
 * Blood alcohol calculation result
 */
export interface BloodAlcoholResult {
  /** Current blood alcohol level (g/L approximation) */
  bloodAlcoholLevel: number;
  /** Alcohol still being absorbed (grams) */
  alcoholAbsorbing: number;
  /** Alcohol in system (grams) */
  alcoholInSystem: number;
  /** Current insulin sensitivity modifier */
  insulinSensitivityModifier: number;
  /** Time until sober (BAL < 0.01) */
  estimatedSoberTime: Date | null;
  /** Breakdown by drink */
  drinkContributions: DrinkContribution[];
}

/**
 * Contribution from a single drink
 */
export interface DrinkContribution {
  /** Original meal event ID (drinks stored as meals with alcoholUnits) */
  eventId: string;
  /** Drink timestamp */
  timestamp: Date;
  /** Original alcohol units */
  alcoholUnits: number;
  /** Alcohol grams (units * 8g standard) */
  alcoholGrams: number;
  /** Drink type */
  drinkType: AlcoholType;
  /** Remaining alcohol in system from this drink */
  remainingGrams: number;
  /** Minutes since drink */
  minutesSinceDrink: number;
}

/**
 * Time-of-day sensitivity factors
 */
export interface CircadianFactors {
  /** Hour of day (0-23) */
  hour: number;
  /** Insulin sensitivity multiplier (1.0 = baseline) */
  insulinSensitivity: number;
  /** Dawn phenomenon factor (higher in early morning) */
  dawnEffect: number;
  /** Combined adjustment factor */
  combinedFactor: number;
}

/**
 * User-specific model parameters (learned from data)
 */
export interface UserModelParameters {
  /** User's insulin sensitivity factor (units carbs per unit insulin) */
  insulinToCarbRatio: number;
  /** User's correction factor (BSL drop per unit insulin in mmol/L) */
  correctionFactor: number;
  /** Target BSL in mmol/L */
  targetBSL: number;
  /** Body weight in kg (affects alcohol metabolism) */
  bodyWeightKg: number;
  /** Custom time-of-day adjustments */
  circadianAdjustments?: Partial<Record<number, number>>;
}

/**
 * BSL prediction result
 */
export interface BSLPrediction {
  /** Predicted BSL at target time in mmol/L */
  predictedBSL: number;
  /** Current BSL used as baseline */
  currentBSL: number;
  /** Confidence interval (low, high) */
  confidenceInterval: [number, number];
  /** Confidence level (0-1) */
  confidence: number;
  /** Factors contributing to prediction */
  factors: BSLPredictionFactors;
  /** Prediction timestamp */
  predictionTime: Date;
  /** Target time for prediction */
  targetTime: Date;
}

/**
 * Factors contributing to BSL prediction
 */
export interface BSLPredictionFactors {
  /** Expected BSL change from active insulin */
  insulinEffect: number;
  /** Expected BSL change from active carbs */
  carbEffect: number;
  /** Expected BSL change from alcohol effects */
  alcoholEffect: number;
  /** Time-of-day adjustment */
  circadianAdjustment: number;
  /** Baseline drift (without any inputs) */
  baselineDrift: number;
}

/**
 * Insulin dose recommendation
 */
export interface InsulinRecommendation {
  /** Recommended dose in units */
  recommendedDose: number;
  /** Confidence interval (low, high) */
  confidenceInterval: [number, number];
  /** Confidence level (0-1) */
  confidence: number;
  /** Breakdown of dose calculation */
  breakdown: DoseBreakdown;
  /** Warnings or alerts */
  warnings: string[];
  /** Recommendation timestamp */
  timestamp: Date;
}

/**
 * Breakdown of insulin dose calculation
 */
export interface DoseBreakdown {
  /** Dose for carb coverage */
  carbCoverage: number;
  /** Dose for BSL correction */
  correctionDose: number;
  /** Adjustment for insulin on board */
  iobAdjustment: number;
  /** Adjustment for active carbs */
  cobAdjustment: number;
  /** Adjustment for alcohol effects */
  alcoholAdjustment: number;
  /** Time-of-day adjustment */
  circadianAdjustment: number;
}

/**
 * Model state snapshot for a point in time
 */
export interface MetabolicState {
  /** Timestamp of state */
  timestamp: Date;
  /** Active insulin state */
  insulin: ActiveInsulinResult;
  /** Active carbs state */
  carbs: ActiveCarbsResult;
  /** Alcohol state */
  alcohol: BloodAlcoholResult;
  /** Circadian factors */
  circadian: CircadianFactors;
  /** Last known BSL */
  lastBSL?: {
    value: number;
    timestamp: Date;
    source: string;
  };
}

/**
 * Time series prediction for charting
 */
export interface BSLTimeSeries {
  /** Array of time points */
  points: BSLTimeSeriesPoint[];
  /** Start time */
  startTime: Date;
  /** End time */
  endTime: Date;
  /** Resolution in minutes */
  resolutionMinutes: number;
}

/**
 * Single point in BSL time series
 */
export interface BSLTimeSeriesPoint {
  /** Timestamp */
  timestamp: Date;
  /** Predicted BSL */
  predictedBSL: number;
  /** Lower confidence bound */
  lowerBound: number;
  /** Upper confidence bound */
  upperBound: number;
  /** Metabolic state at this point */
  state: MetabolicState;
}

/**
 * Event window for model calculations
 */
export interface EventWindow {
  /** Insulin events in window */
  insulinEvents: PhysiologicalEvent[];
  /** Meal events in window */
  mealEvents: PhysiologicalEvent[];
  /** BSL events in window */
  bslEvents: PhysiologicalEvent[];
  /** Window start time */
  startTime: Date;
  /** Window end time */
  endTime: Date;
}
