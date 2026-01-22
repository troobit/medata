/**
 * Modeling Services
 *
 * Regression and prediction models for blood sugar management.
 */

// Insulin decay model
export {
  INSULIN_KINETICS,
  calculateInsulinActivity,
  generateActivityCurve,
  calculateActiveInsulin,
  estimateInsulinBSLEffect,
  assessInsulinStacking,
  projectInsulinActivity
} from './InsulinDecayModel';

// Carbohydrate absorption model
export {
  GI_ESTIMATES,
  getAbsorptionParams,
  estimateGlycemicIndex,
  calculateCarbAbsorption,
  generateAbsorptionCurve,
  calculateActiveCarbs,
  estimateCarbBSLEffect,
  projectCarbAbsorption
} from './CarbAbsorptionModel';

// Alcohol metabolism model
export {
  STANDARD_DRINK_GRAMS,
  ALCOHOL_PARAMS,
  BODY_DISTRIBUTION_FACTOR,
  adjustEliminationRate,
  calculateBAL,
  calculateAlcoholState,
  calculateBloodAlcohol,
  estimateTimeUntilSober,
  getHypoglycemiaRiskWindow,
  projectAlcoholMetabolism
} from './AlcoholMetabolismModel';

// Circadian (time-of-day) model
export {
  DEFAULT_CIRCADIAN_PATTERN,
  DAWN_PHENOMENON_PATTERN,
  calculateCircadianFactors,
  interpolateCircadianFactors,
  adjustDoseForTimeOfDay,
  estimateCircadianBSLDrift,
  generateCircadianCurve,
  analyzeOvernightPattern
} from './CircadianModel';

// BSL prediction model
export {
  DEFAULT_USER_PARAMETERS,
  calculateMetabolicState,
  calculatePredictionFactors,
  predictBSL,
  generateBSLTimeSeries,
  buildEventWindow,
  estimateTimeToTarget,
  checkForAlerts
} from './BSLPredictionModel';

// Insulin recommendation engine
export {
  calculateMealDose,
  calculateCorrectionDose,
  getTimingRecommendation,
  suggestICRAdjustment,
  explainRecommendation
} from './InsulinRecommendationEngine';
