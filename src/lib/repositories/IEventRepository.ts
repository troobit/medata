import type { PhysiologicalEvent, CreateEventInput, UpdateEventInput, EventType } from '$lib/types';

/**
 * Repository interface for physiological events
 * Implementations can use IndexedDB, REST API, or other storage backends
 */
export interface IEventRepository {
  // CRUD operations
  create(event: CreateEventInput): Promise<PhysiologicalEvent>;
  getById(id: string): Promise<PhysiologicalEvent | null>;
  update(id: string, updates: UpdateEventInput): Promise<PhysiologicalEvent>;
  delete(id: string): Promise<void>;

  // Query operations
  getByDateRange(start: Date, end: Date): Promise<PhysiologicalEvent[]>;
  getByType(type: EventType, limit?: number): Promise<PhysiologicalEvent[]>;
  getRecent(limit: number): Promise<PhysiologicalEvent[]>;

  // Bulk operations
  bulkCreate(events: CreateEventInput[]): Promise<PhysiologicalEvent[]>;
  exportAll(): Promise<PhysiologicalEvent[]>;
  importBulk(events: PhysiologicalEvent[]): Promise<void>;
  clear(): Promise<void>;
}
