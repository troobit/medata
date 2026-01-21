import type {
  UserSettings,
  AIProvider,
  FoundryConfig,
  AzureConfig,
  BedrockConfig,
  LocalModelConfig
} from '$lib/types';
import type { ISettingsRepository } from '$lib/repositories';
import { mergeWithEnvSettings } from '$lib/config';

/**
 * Business logic layer for user settings
 * Framework-agnostic - returns Promises, no Svelte imports
 *
 * Settings are merged from two sources:
 * 1. Environment variables (via .env files)
 * 2. User settings (stored in localStorage)
 *
 * User settings take precedence over environment variables.
 */
export class SettingsService {
  constructor(private repository: ISettingsRepository) {}

  /**
   * Gets settings merged from env vars and user storage.
   * User-configured values take precedence over env vars.
   */
  async getSettings(): Promise<UserSettings> {
    const userSettings = await this.repository.get();
    return mergeWithEnvSettings(userSettings);
  }

  /**
   * Gets raw user settings without env var merging.
   * Useful for settings UI to show what the user has explicitly configured.
   */
  async getUserSettings(): Promise<UserSettings> {
    return this.repository.get();
  }

  async updateSettings(updates: Partial<UserSettings>): Promise<UserSettings> {
    const updated = await this.repository.update(updates);
    return mergeWithEnvSettings(updated);
  }

  async resetSettings(): Promise<void> {
    return this.repository.clear();
  }

  // API Key management for direct API providers
  async setApiKey(provider: AIProvider, key: string): Promise<UserSettings> {
    const keyMap: Partial<Record<AIProvider, keyof UserSettings>> = {
      openai: 'openaiApiKey',
      gemini: 'geminiApiKey',
      claude: 'claudeApiKey'
    };

    const settingKey = keyMap[provider];
    if (!settingKey) {
      throw new Error(
        `Provider "${provider}" uses config objects instead of API keys. Use setProviderConfig instead.`
      );
    }

    return this.updateSettings({
      [settingKey]: key,
      aiProvider: provider
    });
  }

  async getApiKey(provider: AIProvider): Promise<string | undefined> {
    const settings = await this.getSettings();
    const keyMap: Partial<Record<AIProvider, keyof UserSettings>> = {
      openai: 'openaiApiKey',
      gemini: 'geminiApiKey',
      claude: 'claudeApiKey'
    };

    const settingKey = keyMap[provider];
    if (!settingKey) return undefined;

    return settings[settingKey] as string | undefined;
  }

  async clearApiKey(provider: AIProvider): Promise<UserSettings> {
    const keyMap: Partial<Record<AIProvider, keyof UserSettings>> = {
      openai: 'openaiApiKey',
      gemini: 'geminiApiKey',
      claude: 'claudeApiKey'
    };

    const settingKey = keyMap[provider];
    if (!settingKey) {
      throw new Error(`Provider "${provider}" uses config objects. Use clearProviderConfig instead.`);
    }

    return this.updateSettings({ [settingKey]: undefined });
  }

  // Config management for Foundry, Azure, Bedrock, and Local providers
  async setFoundryConfig(config: FoundryConfig): Promise<UserSettings> {
    return this.updateSettings({
      foundryConfig: config,
      aiProvider: 'foundry'
    });
  }

  async setAzureConfig(config: AzureConfig): Promise<UserSettings> {
    return this.updateSettings({
      azureConfig: config,
      aiProvider: 'azure'
    });
  }

  async setBedrockConfig(config: BedrockConfig): Promise<UserSettings> {
    return this.updateSettings({
      bedrockConfig: config,
      aiProvider: 'bedrock'
    });
  }

  async setLocalModelConfig(config: LocalModelConfig): Promise<UserSettings> {
    return this.updateSettings({
      localModelConfig: config,
      aiProvider: 'local'
    });
  }

  async clearProviderConfig(provider: 'foundry' | 'azure' | 'bedrock' | 'local'): Promise<UserSettings> {
    const configMap: Record<typeof provider, keyof UserSettings> = {
      foundry: 'foundryConfig',
      azure: 'azureConfig',
      bedrock: 'bedrockConfig',
      local: 'localModelConfig'
    };

    return this.updateSettings({ [configMap[provider]]: undefined });
  }

  async isAIConfigured(): Promise<boolean> {
    const settings = await this.getSettings();
    return !!(
      settings.foundryConfig?.apiKey ||
      settings.openaiApiKey ||
      settings.geminiApiKey ||
      settings.claudeApiKey ||
      settings.azureConfig?.apiKey ||
      settings.bedrockConfig?.accessKeyId ||
      settings.localModelConfig?.endpoint
    );
  }

  async getConfiguredProvider(): Promise<AIProvider | null> {
    const settings = await this.getSettings();

    // Check if preferred provider is configured
    if (settings.aiProvider) {
      if (this.isProviderConfigured(settings, settings.aiProvider)) {
        return settings.aiProvider;
      }
    }

    // Fallback to first configured provider (foundry first for Azure users)
    const providers: AIProvider[] = [
      'foundry',
      'openai',
      'gemini',
      'claude',
      'azure',
      'bedrock',
      'local'
    ];
    for (const provider of providers) {
      if (this.isProviderConfigured(settings, provider)) {
        return provider;
      }
    }

    return null;
  }

  private isProviderConfigured(settings: UserSettings, provider: AIProvider): boolean {
    switch (provider) {
      case 'foundry':
        return !!(settings.foundryConfig?.apiKey && settings.foundryConfig?.endpoint);
      case 'openai':
        return !!settings.openaiApiKey;
      case 'gemini':
        return !!settings.geminiApiKey;
      case 'claude':
        return !!settings.claudeApiKey;
      case 'azure':
        return !!(settings.azureConfig?.apiKey && settings.azureConfig?.endpoint);
      case 'bedrock':
        return !!(
          settings.bedrockConfig?.accessKeyId &&
          settings.bedrockConfig?.secretAccessKey &&
          settings.bedrockConfig?.region
        );
      case 'local':
        return !!settings.localModelConfig?.endpoint;
      default:
        return false;
    }
  }
}
