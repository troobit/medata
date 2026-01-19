import type { BSLUnit, InsulinType } from './events';

/**
 * ML provider options for food recognition
 * - Cloud providers: openai, gemini, claude, foundry
 * - Self-hosted: ollama
 */
export type MLProvider = 'openai' | 'gemini' | 'claude' | 'foundry' | 'ollama';

/**
 * @deprecated Use MLProvider instead
 */
export type AIProvider = MLProvider;

/**
 * User preferences and settings
 */
export interface UserSettings {
  // ML Configuration (cloud providers)
  aiProvider?: MLProvider;
  openaiApiKey?: string;
  geminiApiKey?: string;
  claudeApiKey?: string;

  // Microsoft Foundry configuration
  foundryEndpoint?: string; // e.g., https://<service>.services.ai.azure.com/api/projects/<project>
  foundryApiKey?: string;

  // Self-hosted Ollama configuration
  ollamaEndpoint?: string; // e.g., http://localhost:11434
  ollamaModel?: string; // e.g., llava, bakllava

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
