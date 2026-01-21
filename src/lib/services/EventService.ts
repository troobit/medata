import type {
  PhysiologicalEvent,
  CreateEventInput,
  UpdateEventInput,
  EventType,
  InsulinType,
  BSLUnit,
  BSLDataSource,
  InsulinMetadata,
  BSLMetadata,
  MealMetadata,
  ExerciseMetadata,
  ExerciseIntensity
} from '$lib/types';
import type { IEventRepository } from '$lib/repositories';

/**
 * Business logic layer for physiological events
 * Framework-agnostic - returns Promises, no Svelte imports
 */
export class EventService {
  constructor(private repository: IEventRepository) {}

  // CRUD operations
  async createEvent(input: CreateEventInput): Promise<PhysiologicalEvent> {
    return this.repository.create(input);
  }

  async getEvent(id: string): Promise<PhysiologicalEvent | null> {
    return this.repository.getById(id);
  }

  async updateEvent(id: string, updates: UpdateEventInput): Promise<PhysiologicalEvent> {
    return this.repository.update(id, updates);
  }

  async deleteEvent(id: string): Promise<void> {
    return this.repository.delete(id);
  }

  // Query operations
  async getEventsByDateRange(start: Date, end: Date): Promise<PhysiologicalEvent[]> {
    return this.repository.getByDateRange(start, end);
  }

  async getEventsByType(type: EventType, limit?: number): Promise<PhysiologicalEvent[]> {
    return this.repository.getByType(type, limit);
  }

  async getRecentEvents(limit: number = 20): Promise<PhysiologicalEvent[]> {
    return this.repository.getRecent(limit);
  }

  // Convenience methods for specific event types
  async logInsulin(
    units: number,
    type: InsulinType,
    timestamp: Date = new Date()
  ): Promise<PhysiologicalEvent> {
    const metadata: InsulinMetadata = { type };
    return this.createEvent({
      timestamp,
      eventType: 'insulin',
      value: units,
      metadata
    });
  }

  async logBSL(
    value: number,
    unit: BSLUnit = 'mmol/L',
    timestamp: Date = new Date(),
    options?: { isFingerPrick?: boolean; device?: string; source?: BSLDataSource }
  ): Promise<PhysiologicalEvent> {
    const metadata: BSLMetadata = {
      unit,
      source: options?.source ?? 'manual',
      ...(options?.isFingerPrick !== undefined && { isFingerPrick: options.isFingerPrick }),
      ...(options?.device && { device: options.device })
    };
    return this.createEvent({
      timestamp,
      eventType: 'bsl',
      value,
      metadata
    });
  }

  async logMeal(
    carbs: number,
    metadata: Partial<MealMetadata> = {},
    timestamp: Date = new Date()
  ): Promise<PhysiologicalEvent> {
    const fullMetadata: MealMetadata = {
      carbs,
      ...metadata
    };
    return this.createEvent({
      timestamp,
      eventType: 'meal',
      value: carbs,
      metadata: fullMetadata
    });
  }

  async logExercise(
    durationMinutes: number,
    intensity: ExerciseIntensity,
    metadata: Partial<ExerciseMetadata> = {},
    timestamp: Date = new Date()
  ): Promise<PhysiologicalEvent> {
    const fullMetadata: ExerciseMetadata = {
      intensity,
      durationMinutes,
      ...metadata
    };
    return this.createEvent({
      timestamp,
      eventType: 'exercise',
      value: durationMinutes,
      metadata: fullMetadata
    });
  }

  /**
   * Log multiple BSL readings at once (e.g., from image import)
   */
  async bulkLogBSL(
    readings: Array<{ value: number; unit: BSLUnit; timestamp: Date; source?: BSLDataSource }>
  ): Promise<PhysiologicalEvent[]> {
    const events: PhysiologicalEvent[] = [];
    for (const reading of readings) {
      const metadata: BSLMetadata = {
        unit: reading.unit,
        source: reading.source || 'cgm-image'
      };
      const event = await this.createEvent({
        timestamp: reading.timestamp,
        eventType: 'bsl',
        value: reading.value,
        metadata
      });
      events.push(event);
    }
    return events;
  }

  // Bulk operations
  async exportAllEvents(): Promise<PhysiologicalEvent[]> {
    return this.repository.exportAll();
  }

  async importEvents(events: PhysiologicalEvent[]): Promise<void> {
    return this.repository.importBulk(events);
  }

  async clearAllEvents(): Promise<void> {
    return this.repository.clear();
  }

  // Utility methods
  async getTodaysEvents(): Promise<PhysiologicalEvent[]> {
    const now = new Date();
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
    return this.getEventsByDateRange(startOfDay, endOfDay);
  }

  async getLastInsulinDose(): Promise<PhysiologicalEvent | null> {
    const events = await this.repository.getByType('insulin', 1);
    return events.length > 0 ? events[events.length - 1] : null;
  }

  /**
   * Get unique recent insulin dose values filtered by insulin type
   * Returns an array of unique dose values (most recent first)
   */
  async getRecentInsulinDoses(insulinType: InsulinType, maxUnique: number = 6): Promise<number[]> {
    // Get recent insulin events (more than maxUnique to find unique values)
    const events = await this.repository.getByType('insulin', 50);

    // Filter by insulin type and extract unique values
    const uniqueDoses = new Set<number>();
    for (const event of events) {
      if (event.metadata && 'type' in event.metadata && event.metadata.type === insulinType) {
        uniqueDoses.add(event.value);
        if (uniqueDoses.size >= maxUnique) break;
      }
    }

    return Array.from(uniqueDoses);
  }

  /**
   * Get recent unique BSL values
   */
  async getRecentBSLValues(limit: number = 5): Promise<number[]> {
    const events = await this.repository.getByType('bsl', 50);
    const uniqueValues = new Set<number>();

    for (const event of events) {
      uniqueValues.add(event.value);
      if (uniqueValues.size >= limit) break;
    }

    return Array.from(uniqueValues);
  }

  /**
   * Get recent unique carb values from meals
   */
  async getRecentCarbValues(maxUnique: number = 6): Promise<number[]> {
    const events = await this.repository.getByType('meal', 50);
    const uniqueValues = new Set<number>();

    for (const event of events) {
      if (event.metadata && 'carbs' in event.metadata) {
        uniqueValues.add(event.metadata.carbs as number);
        if (uniqueValues.size >= maxUnique) break;
      }
    }

    return Array.from(uniqueValues);
  }
}
