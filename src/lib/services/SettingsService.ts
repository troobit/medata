import type { UserSettings, MLProvider, AIProvider } from '$lib/types';
import type { ISettingsRepository } from '$lib/repositories';

// Map of cloud providers to their API key field
type CloudProvider = 'openai' | 'gemini' | 'claude';
const CLOUD_KEY_MAP: Record<CloudProvider, keyof UserSettings> = {
  openai: 'openaiApiKey',
  gemini: 'geminiApiKey',
  claude: 'claudeApiKey'
};

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

  // API Key management for cloud providers
  async setApiKey(provider: AIProvider, key: string): Promise<UserSettings> {
    if (provider === 'foundry' || provider === 'ollama') {
      throw new Error(`Use updateSettings() for ${provider} configuration`);
    }

    const keyField = CLOUD_KEY_MAP[provider as CloudProvider];
    return this.updateSettings({
      [keyField]: key,
      aiProvider: provider
    });
  }

  async getApiKey(provider: AIProvider): Promise<string | undefined> {
    const settings = await this.getSettings();

    if (provider === 'foundry') return settings.foundryApiKey;
    if (provider === 'ollama') return undefined; // Ollama doesn't use API keys

    const keyField = CLOUD_KEY_MAP[provider as CloudProvider];
    return settings[keyField] as string | undefined;
  }

  async clearApiKey(provider: AIProvider): Promise<UserSettings> {
    if (provider === 'foundry') {
      return this.updateSettings({ foundryApiKey: undefined, foundryEndpoint: undefined });
    }
    if (provider === 'ollama') {
      return this.updateSettings({ ollamaEndpoint: undefined, ollamaModel: undefined });
    }

    const keyField = CLOUD_KEY_MAP[provider as CloudProvider];
    return this.updateSettings({ [keyField]: undefined });
  }

  async isMLConfigured(): Promise<boolean> {
    const settings = await this.getSettings();
    return !!(
      settings.openaiApiKey ||
      settings.geminiApiKey ||
      settings.claudeApiKey ||
      (settings.foundryEndpoint && settings.foundryApiKey) ||
      settings.ollamaEndpoint
    );
  }

  /** @deprecated Use isMLConfigured instead */
  async isAIConfigured(): Promise<boolean> {
    return this.isMLConfigured();
  }

  async getConfiguredProvider(): Promise<MLProvider | null> {
    const settings = await this.getSettings();

    // Check explicit provider preference first
    if (settings.aiProvider && (await this.isProviderConfigured(settings.aiProvider))) {
      return settings.aiProvider;
    }

    // Fallback to first configured provider
    if (settings.openaiApiKey) return 'openai';
    if (settings.geminiApiKey) return 'gemini';
    if (settings.claudeApiKey) return 'claude';
    if (settings.foundryEndpoint && settings.foundryApiKey) return 'foundry';
    if (settings.ollamaEndpoint) return 'ollama';

    return null;
  }

  private async isProviderConfigured(provider: MLProvider): Promise<boolean> {
    const settings = await this.getSettings();
    switch (provider) {
      case 'openai':
        return !!settings.openaiApiKey;
      case 'gemini':
        return !!settings.geminiApiKey;
      case 'claude':
        return !!settings.claudeApiKey;
      case 'foundry':
        return !!(settings.foundryEndpoint && settings.foundryApiKey);
      case 'ollama':
        return !!settings.ollamaEndpoint;
    }
  }
}
