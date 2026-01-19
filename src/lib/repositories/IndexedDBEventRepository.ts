import { v4 as uuidv4 } from 'uuid';
import { db } from '$lib/db';
import type { PhysiologicalEvent, CreateEventInput, UpdateEventInput, EventType } from '$lib/types';
import type { IEventRepository } from './IEventRepository';

/**
 * IndexedDB implementation of the event repository using Dexie.js
 */
export class IndexedDBEventRepository implements IEventRepository {
  async create(input: CreateEventInput): Promise<PhysiologicalEvent> {
    const now = new Date();
    const event: PhysiologicalEvent = {
      ...input,
      id: uuidv4(),
      createdAt: now,
      updatedAt: now
    };

    await db.events.add(event);
    return event;
  }

  async getById(id: string): Promise<PhysiologicalEvent | null> {
    const event = await db.events.get(id);
    return event ?? null;
  }

  async update(id: string, updates: UpdateEventInput): Promise<PhysiologicalEvent> {
    const existing = await this.getById(id);
    if (!existing) {
      throw new Error(`Event with id ${id} not found`);
    }

    const updated: PhysiologicalEvent = {
      ...existing,
      ...updates,
      updatedAt: new Date()
    };

    await db.events.put(updated);
    return updated;
  }

  async delete(id: string): Promise<void> {
    await db.events.delete(id);
  }

  async getByDateRange(start: Date, end: Date): Promise<PhysiologicalEvent[]> {
    return db.events.where('timestamp').between(start, end, true, true).sortBy('timestamp');
  }

  async getByType(type: EventType, limit?: number): Promise<PhysiologicalEvent[]> {
    const query = db.events.where('eventType').equals(type).reverse();

    if (limit) {
      return query.limit(limit).sortBy('timestamp');
    }

    return query.sortBy('timestamp');
  }

  async getRecent(limit: number): Promise<PhysiologicalEvent[]> {
    return db.events.orderBy('timestamp').reverse().limit(limit).toArray();
  }

  async bulkCreate(inputs: CreateEventInput[]): Promise<PhysiologicalEvent[]> {
    const now = new Date();
    const events: PhysiologicalEvent[] = inputs.map((input) => ({
      ...input,
      id: uuidv4(),
      createdAt: now,
      updatedAt: now
    }));

    await db.events.bulkAdd(events);
    return events;
  }

  async exportAll(): Promise<PhysiologicalEvent[]> {
    return db.events.toArray();
  }

  async importBulk(events: PhysiologicalEvent[]): Promise<void> {
    await db.events.bulkPut(events);
  }

  async clear(): Promise<void> {
    await db.events.clear();
  }
}
