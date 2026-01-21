import { getEventService } from '$lib/services';
import type {
  PhysiologicalEvent,
  EventType,
  InsulinType,
  BSLUnit,
  BSLDataSource,
  MealMetadata
} from '$lib/types';

/**
 * Reactive store for physiological events using Svelte 5 runes
 */
function createEventsStore() {
  let events = $state<PhysiologicalEvent[]>([]);
  let loading = $state(false);
  let error = $state<string | null>(null);

  const service = getEventService();

  async function loadRecent(limit: number = 20) {
    loading = true;
    error = null;
    try {
      events = await service.getRecentEvents(limit);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load events';
    } finally {
      loading = false;
    }
  }

  async function loadToday() {
    loading = true;
    error = null;
    try {
      events = await service.getTodaysEvents();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load events';
    } finally {
      loading = false;
    }
  }

  async function loadByDateRange(start: Date, end: Date) {
    loading = true;
    error = null;
    try {
      events = await service.getEventsByDateRange(start, end);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load events';
    } finally {
      loading = false;
    }
  }

  async function loadByType(type: EventType, limit?: number) {
    loading = true;
    error = null;
    try {
      events = await service.getEventsByType(type, limit);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load events';
    } finally {
      loading = false;
    }
  }

  async function logInsulin(units: number, type: InsulinType, timestamp?: Date) {
    loading = true;
    error = null;
    try {
      const event = await service.logInsulin(units, type, timestamp);
      events = [event, ...events];
      return event;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to log insulin';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function logBSL(
    value: number,
    unit?: BSLUnit,
    timestamp?: Date,
    options?: { isFingerPrick?: boolean; device?: string; source?: BSLDataSource }
  ) {
    loading = true;
    error = null;
    try {
      const event = await service.logBSL(value, unit, timestamp, options);
      events = [event, ...events];
      return event;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to log BSL';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function getRecentBSLValues(limit?: number) {
    return service.getRecentBSLValues(limit);
  }

  async function logMeal(carbs: number, metadata?: Partial<MealMetadata>, timestamp?: Date) {
    loading = true;
    error = null;
    try {
      const event = await service.logMeal(carbs, metadata, timestamp);
      events = [event, ...events];
      return event;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to log meal';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function bulkLogBSL(
    readings: Array<{ value: number; unit: BSLUnit; timestamp: Date; source?: BSLDataSource }>
  ) {
    loading = true;
    error = null;
    try {
      const newEvents = await service.bulkLogBSL(readings);
      events = [...newEvents, ...events];
      return newEvents;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to import BSL readings';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function deleteEvent(id: string) {
    loading = true;
    error = null;
    try {
      await service.deleteEvent(id);
      events = events.filter((e) => e.id !== id);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to delete event';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function updateEvent(id: string, updates: Partial<PhysiologicalEvent>) {
    loading = true;
    error = null;
    try {
      const updated = await service.updateEvent(id, updates);
      events = events.map((e) => (e.id === id ? updated : e));
      return updated;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to update event';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function getRecentInsulinDoses(insulinType: 'bolus' | 'basal', maxUnique: number = 6) {
    try {
      return await service.getRecentInsulinDoses(insulinType, maxUnique);
    } catch {
      return [];
    }
  }

  async function getRecentCarbValues(maxUnique: number = 6) {
    try {
      return await service.getRecentCarbValues(maxUnique);
    } catch {
      return [];
    }
  }

  return {
    get events() {
      return events;
    },
    get loading() {
      return loading;
    },
    get error() {
      return error;
    },
    loadRecent,
    loadToday,
    loadByDateRange,
    loadByType,
    logInsulin,
    logBSL,
    logMeal,
    bulkLogBSL,
    deleteEvent,
    updateEvent,
    getRecentInsulinDoses,
    getRecentBSLValues,
    getRecentCarbValues
  };
}

export const eventsStore = createEventsStore();
