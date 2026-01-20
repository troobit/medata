/**
 * Workstream C: Local Food Volume Estimation Services
 * Branch: dev-3
 *
 * Browser-local food volume estimation using reference objects.
 * No cloud API calls - all processing happens on device.
 */

// Main orchestrator
export { EstimationEngine, estimationEngine } from './EstimationEngine';
export type { EstimationState } from './EstimationEngine';

// Reference detection
export { ReferenceDetector, referenceDetector } from './ReferenceDetector';

// Volume calculation
export { VolumeCalculator, volumeCalculator, SHAPE_TEMPLATES } from './VolumeCalculator';
export type { ShapeTemplate } from './VolumeCalculator';

// Food density lookup
export { FoodDensityLookup, foodDensityLookup } from './FoodDensityLookup';
export type { SearchResult } from './FoodDensityLookup';

// Calibration from user corrections
export { CalibrationStore, calibrationStore } from './CalibrationStore';
export type { CorrectionInput } from './CalibrationStore';
