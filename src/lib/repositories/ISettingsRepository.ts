import type { UserSettings } from '$lib/types';

/**
 * Repository interface for user settings
 * Settings are typically stored in localStorage for simplicity
 */
export interface ISettingsRepository {
  get(): Promise<UserSettings>;
  save(settings: UserSettings): Promise<void>;
  update(updates: Partial<UserSettings>): Promise<UserSettings>;
  clear(): Promise<void>;
}
