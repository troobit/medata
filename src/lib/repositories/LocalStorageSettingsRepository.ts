import type { UserSettings } from '$lib/types';
import { DEFAULT_SETTINGS } from '$lib/types';
import type { ISettingsRepository } from './ISettingsRepository';

const STORAGE_KEY = 'medata_settings';

/**
 * LocalStorage implementation of the settings repository
 */
export class LocalStorageSettingsRepository implements ISettingsRepository {
  async get(): Promise<UserSettings> {
    if (typeof window === 'undefined') {
      return DEFAULT_SETTINGS;
    }

    const stored = localStorage.getItem(STORAGE_KEY);
    if (!stored) {
      return DEFAULT_SETTINGS;
    }

    try {
      const parsed = JSON.parse(stored);
      return { ...DEFAULT_SETTINGS, ...parsed };
    } catch {
      return DEFAULT_SETTINGS;
    }
  }

  async save(settings: UserSettings): Promise<void> {
    if (typeof window === 'undefined') {
      return;
    }

    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
  }

  async update(updates: Partial<UserSettings>): Promise<UserSettings> {
    const current = await this.get();
    const updated = { ...current, ...updates };
    await this.save(updated);
    return updated;
  }

  async clear(): Promise<void> {
    if (typeof window === 'undefined') {
      return;
    }

    localStorage.removeItem(STORAGE_KEY);
  }
}
