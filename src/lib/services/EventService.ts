import type {
  PhysiologicalEvent,
  CreateEventInput,
  UpdateEventInput,
  EventType,
  InsulinType,
  BSLUnit,
  InsulinMetadata,
  BSLMetadata,
  MealMetadata
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
    timestamp: Date = new Date()
  ): Promise<PhysiologicalEvent> {
    const metadata: BSLMetadata = { unit };
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

  async getRecentInsulinDosesByType(
    insulinType: InsulinType,
    limit: number = 10
  ): Promise<number[]> {
    const events = await this.repository.getByType('insulin', 50);
    const doses = events
      .filter((e) => e.metadata && (e.metadata as InsulinMetadata).type === insulinType)
      .map((e) => e.value)
      .slice(0, limit);

    // Return unique values only
    return [...new Set(doses)];
  }
}
