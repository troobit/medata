import type { BSLUnit, InsulinType } from './events';

/**
 * AI provider options for food recognition
 */
export type AIProvider = 'openai' | 'gemini' | 'claude';

/**
 * User preferences and settings
 */
export interface UserSettings {
  // AI Configuration
  aiProvider?: AIProvider;
  openaiApiKey?: string;
  geminiApiKey?: string;
  claudeApiKey?: string;

  // Defaults
  defaultInsulinType: InsulinType;
  defaultBSLUnit: BSLUnit;

  // Display
  darkMode: 'system' | 'light' | 'dark';

  // Data
  lastSyncTimestamp?: Date;
}

/**
 * Default settings for new users
 */
export const DEFAULT_SETTINGS: UserSettings = {
  defaultInsulinType: 'bolus',
  defaultBSLUnit: 'mmol/L',
  darkMode: 'system'
};
