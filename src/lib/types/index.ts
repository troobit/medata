// Events
export type {
  EventType,
  InsulinType,
  BSLUnit,
  ExerciseIntensity,
  ExerciseCategory,
  ExerciseDataSource,
  AlcoholType,
  MacroData,
  MealMetadata,
  MealItem,
  InsulinMetadata,
  BSLMetadata,
  ExerciseMetadata,
  EventMetadata,
  PhysiologicalEvent,
  CreateEventInput,
  UpdateEventInput,
  // Source tracking types (for workstreams)
  MealDataSource,
  BSLDataSource,
  CorrectionRecord
} from './events';

export { isMealMetadata, isInsulinMetadata, isBSLMetadata, isExerciseMetadata } from './events';

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
export type {
  AIProvider,
  UserSettings,
  FoundryConfig,
  AzureConfig,
  BedrockConfig,
  LocalModelConfig
} from './settings';
export { DEFAULT_SETTINGS, ENV_VAR_NAMES } from './settings';

// Workstream A: AI Food Recognition
export type {
  BoundingBox,
  RecognizedFoodItem,
  FoodRecognitionResult,
  NutritionLabelResult,
  RecognitionOptions,
  IFoodRecognitionService
} from './ai';

// Workstream B: CGM Graph Capture
export type {
  CGMDeviceType,
  AxisRanges,
  ExtractedDataPoint,
  GraphRegion,
  CGMExtractionResult,
  CGMExtractionOptions,
  ICGMImageService
} from './cgm';

// CGM API Integration (Task 22)
export type {
  CGMApiProvider,
  LibreLinkConfig,
  DexcomShareConfig,
  NightscoutConfig,
  CGMApiConfig,
  CGMAuthSession,
  CGMGlucoseReading,
  CGMTrendDirection,
  CGMFetchResult,
  CGMConnectionStatus,
  CGMFetchOptions,
  ICGMApiService
} from './cgm-api';
export { TREND_ARROWS, dexcomTrendToDirection, libreTrendToDirection } from './cgm-api';

// Workstream C: Local Food Estimation
export type {
  ReferenceObjectType,
  DetectedReference,
  FoodRegion,
  FoodDensityEntry,
  VolumeEstimationResult,
  LocalEstimationResult,
  CalibrationEntry,
  IVolumeEstimationService
} from './local-estimation';
export { REFERENCE_DIMENSIONS } from './local-estimation';

// Workstream D: BSL Data Import
export type {
  CSVFormatType,
  CSVColumnMapping,
  ParsedCSVRow,
  RowValidationResult,
  DuplicateMatch,
  DuplicateStrategy,
  ImportPreview,
  ImportResult,
  CSVImportOptions,
  IImportService,
  IExportService
} from './import';

// AI Model Validation
export type {
  FoodCategory,
  GroundTruthSource,
  TestDatasetEntry,
  ValidationResult,
  MacroErrorMetrics,
  AccuracyMetrics,
  CorrectionHistoryEntry,
  CorrectionPatternStats,
  PromptEnhancement,
  CreateTestDataInput,
  UpdateTestDataInput,
  TestDatasetExport,
  USDAFoodEntry,
  DatasetImportResult
} from './validation';

// Authentication (Task 24)
export type {
  User,
  StoredCredential,
  AuthSession,
  AuthChallenge,
  RegistrationOptions,
  AuthenticationOptions,
  RegistrationResult,
  AuthenticationResult,
  AuthConfig,
  AuthErrorCode
} from './auth';
export {
  DEFAULT_AUTH_CONFIG,
  AuthError,
  isWebAuthnSupported,
  isPlatformAuthenticatorAvailable,
  arrayBufferToBase64,
  base64ToArrayBuffer,
  generateChallenge
} from './auth';

// Regression & Modeling
export type {
  InsulinKinetics,
  InsulinActivityPoint,
  ActiveInsulinResult,
  DoseContribution,
  CarbAbsorptionParams,
  CarbAbsorptionPoint,
  ActiveCarbsResult,
  MealContribution,
  AlcoholMetabolismParams,
  BloodAlcoholResult,
  DrinkContribution,
  CircadianFactors,
  UserModelParameters,
  BSLPrediction,
  BSLPredictionFactors,
  InsulinRecommendation,
  DoseBreakdown,
  MetabolicState,
  BSLTimeSeries,
  BSLTimeSeriesPoint,
  EventWindow
} from './modeling';
