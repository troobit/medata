// Interfaces
export type { IEventRepository } from './IEventRepository';
export type { ISettingsRepository } from './ISettingsRepository';
export type { IPresetRepository } from './IPresetRepository';

// Implementations
export { IndexedDBEventRepository } from './IndexedDBEventRepository';
export { LocalStorageSettingsRepository } from './LocalStorageSettingsRepository';
export { IndexedDBPresetRepository } from './IndexedDBPresetRepository';

// Factory functions for default implementations
import { IndexedDBEventRepository } from './IndexedDBEventRepository';
import { LocalStorageSettingsRepository } from './LocalStorageSettingsRepository';
import { IndexedDBPresetRepository } from './IndexedDBPresetRepository';

let eventRepository: IndexedDBEventRepository | null = null;
let settingsRepository: LocalStorageSettingsRepository | null = null;
let presetRepository: IndexedDBPresetRepository | null = null;

export function getEventRepository(): IndexedDBEventRepository {
  if (!eventRepository) {
    eventRepository = new IndexedDBEventRepository();
  }
  return eventRepository;
}

export function getSettingsRepository(): LocalStorageSettingsRepository {
  if (!settingsRepository) {
    settingsRepository = new LocalStorageSettingsRepository();
  }
  return settingsRepository;
}

export function getPresetRepository(): IndexedDBPresetRepository {
  if (!presetRepository) {
    presetRepository = new IndexedDBPresetRepository();
  }
  return presetRepository;
}
