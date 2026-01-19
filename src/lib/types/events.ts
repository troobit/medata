/**
 * Event types for physiological data logging
 */
export type EventType = 'meal' | 'insulin' | 'bsl' | 'exercise';

/**
 * Insulin type: bolus (fast-acting) or basal (long-acting)
 */
export type InsulinType = 'bolus' | 'basal';

/**
 * BSL unit of measurement
 */
export type BSLUnit = 'mmol/L' | 'mg/dL';

/**
 * Exercise intensity level
 */
export type ExerciseIntensity = 'low' | 'moderate' | 'high';

/**
 * Macro nutrient data for meals
 */
export interface MacroData {
  calories: number;
  carbs: number;
  protein: number;
  fat: number;
}

/**
 * Metadata specific to meal events
 */
export interface MealMetadata extends Partial<MacroData> {
  description?: string;
  photoUrl?: string;
  items?: MealItem[];
  [key: string]: unknown;
}

/**
 * Individual food item within a meal
 */
export interface MealItem {
  name: string;
  quantity?: number;
  unit?: string;
  macros?: Partial<MacroData>;
}

/**
 * Metadata specific to insulin events
 */
export interface InsulinMetadata {
  type: InsulinType;
  [key: string]: unknown;
}

/**
 * Metadata specific to BSL events
 */
export interface BSLMetadata {
  unit: BSLUnit;
  [key: string]: unknown;
}

/**
 * Metadata specific to exercise events
 */
export interface ExerciseMetadata {
  intensity: ExerciseIntensity;
  exerciseType?: string;
  [key: string]: unknown;
}

/**
 * Union type for all possible metadata
 */
export type EventMetadata = MealMetadata | InsulinMetadata | BSLMetadata | ExerciseMetadata;

/**
 * Core event structure - all physiological data follows this pattern
 */
export interface PhysiologicalEvent {
  id: string;
  timestamp: Date;
  eventType: EventType;
  value: number;
  metadata: Record<string, unknown>;
  createdAt: Date;
  updatedAt: Date;
  synced?: boolean;
}

/**
 * Input type for creating a new event (without auto-generated fields)
 */
export type CreateEventInput = Omit<PhysiologicalEvent, 'id' | 'createdAt' | 'updatedAt'>;

/**
 * Input type for updating an existing event
 */
export type UpdateEventInput = Partial<Omit<PhysiologicalEvent, 'id' | 'createdAt'>>;

/**
 * Type guard to check if metadata is MealMetadata
 */
export function isMealMetadata(metadata: Record<string, unknown>): metadata is MealMetadata {
  return (
    'carbs' in metadata ||
    'calories' in metadata ||
    'description' in metadata ||
    'photoUrl' in metadata
  );
}

/**
 * Type guard to check if metadata is InsulinMetadata
 */
export function isInsulinMetadata(metadata: Record<string, unknown>): metadata is InsulinMetadata {
  return 'type' in metadata && (metadata.type === 'bolus' || metadata.type === 'basal');
}

/**
 * Type guard to check if metadata is BSLMetadata
 */
export function isBSLMetadata(metadata: Record<string, unknown>): metadata is BSLMetadata {
  return 'unit' in metadata && (metadata.unit === 'mmol/L' || metadata.unit === 'mg/dL');
}

/**
 * Type guard to check if metadata is ExerciseMetadata
 */
export function isExerciseMetadata(
  metadata: Record<string, unknown>
): metadata is ExerciseMetadata {
  return (
    'intensity' in metadata &&
    (metadata.intensity === 'low' ||
      metadata.intensity === 'moderate' ||
      metadata.intensity === 'high')
  );
}
