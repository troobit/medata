import type { UserSettings, AIProvider } from '$lib/types';
import type { ISettingsRepository } from '$lib/repositories';

/**
 * Business logic layer for user settings
 * Framework-agnostic - returns Promises, no Svelte imports
 */
export class SettingsService {
  constructor(private repository: ISettingsRepository) {}

  async getSettings(): Promise<UserSettings> {
    return this.repository.get();
  }

  async updateSettings(updates: Partial<UserSettings>): Promise<UserSettings> {
    return this.repository.update(updates);
  }

  async resetSettings(): Promise<void> {
    return this.repository.clear();
  }

  // API Key management
  async setApiKey(provider: AIProvider, key: string): Promise<UserSettings> {
    const keyMap: Record<AIProvider, keyof UserSettings> = {
      openai: 'openaiApiKey',
      gemini: 'geminiApiKey',
      claude: 'claudeApiKey'
    };

    return this.updateSettings({
      [keyMap[provider]]: key,
      aiProvider: provider
    });
  }

  async getApiKey(provider: AIProvider): Promise<string | undefined> {
    const settings = await this.getSettings();
    const keyMap: Record<AIProvider, keyof UserSettings> = {
      openai: 'openaiApiKey',
      gemini: 'geminiApiKey',
      claude: 'claudeApiKey'
    };

    return settings[keyMap[provider]] as string | undefined;
  }

  async clearApiKey(provider: AIProvider): Promise<UserSettings> {
    const keyMap: Record<AIProvider, keyof UserSettings> = {
      openai: 'openaiApiKey',
      gemini: 'geminiApiKey',
      claude: 'claudeApiKey'
    };

    return this.updateSettings({ [keyMap[provider]]: undefined });
  }

  async isAIConfigured(): Promise<boolean> {
    const settings = await this.getSettings();
    return !!(settings.openaiApiKey || settings.geminiApiKey || settings.claudeApiKey);
  }

  async getConfiguredProvider(): Promise<AIProvider | null> {
    const settings = await this.getSettings();
    if (settings.aiProvider) {
      const key = await this.getApiKey(settings.aiProvider);
      if (key) return settings.aiProvider;
    }

    // Fallback to first configured provider
    if (settings.openaiApiKey) return 'openai';
    if (settings.geminiApiKey) return 'gemini';
    if (settings.claudeApiKey) return 'claude';

    return null;
  }
}
