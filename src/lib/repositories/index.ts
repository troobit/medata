// Interfaces
export type { IEventRepository } from './IEventRepository';
export type { ISettingsRepository } from './ISettingsRepository';
export type { IPresetRepository } from './IPresetRepository';
export type { IValidationRepository } from './IValidationRepository';

// Implementations
export { IndexedDBEventRepository } from './IndexedDBEventRepository';
export { LocalStorageSettingsRepository } from './LocalStorageSettingsRepository';
export { IndexedDBPresetRepository } from './IndexedDBPresetRepository';
export { IndexedDBValidationRepository } from './IndexedDBValidationRepository';

// Factory functions for default implementations
import { IndexedDBEventRepository } from './IndexedDBEventRepository';
import { LocalStorageSettingsRepository } from './LocalStorageSettingsRepository';
import { IndexedDBPresetRepository } from './IndexedDBPresetRepository';
import { IndexedDBValidationRepository } from './IndexedDBValidationRepository';

let eventRepository: IndexedDBEventRepository | null = null;
let settingsRepository: LocalStorageSettingsRepository | null = null;
let presetRepository: IndexedDBPresetRepository | null = null;
let validationRepository: IndexedDBValidationRepository | null = null;

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

export function getValidationRepository(): IndexedDBValidationRepository {
  if (!validationRepository) {
    validationRepository = new IndexedDBValidationRepository();
  }
  return validationRepository;
}
