// Events
export type {
  EventType,
  InsulinType,
  BSLUnit,
  ExerciseIntensity,
  MacroData,
  MealMetadata,
  MealItem,
  InsulinMetadata,
  BSLMetadata,
  ExerciseMetadata,
  EventMetadata,
  PhysiologicalEvent,
  CreateEventInput,
  UpdateEventInput
} from './events';

export {
  isMealMetadata,
  isInsulinMetadata,
  isBSLMetadata,
  isExerciseMetadata
} from './events';

// Vision
export type {
  ExtractedBSLReading,
  BSLExtractionResult,
  VisionAnalysisOptions,
  OpenAIVisionResponse
} from './vision';

// Presets
export type { MealPreset, CreatePresetInput, UpdatePresetInput } from './presets';

// Settings
export type { AIProvider, UserSettings } from './settings';
export { DEFAULT_SETTINGS } from './settings';
