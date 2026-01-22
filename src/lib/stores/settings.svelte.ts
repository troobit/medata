import { getSettingsService } from '$lib/services';
import type {
  UserSettings,
  AIProvider,
  AzureConfig,
  BedrockConfig,
  LocalModelConfig
} from '$lib/types';
import { DEFAULT_SETTINGS } from '$lib/types';

/**
 * Reactive store for user settings using Svelte 5 runes
 */
function createSettingsStore() {
  let settings = $state<UserSettings>(DEFAULT_SETTINGS);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let initialized = $state(false);

  const service = getSettingsService();

  async function load() {
    loading = true;
    error = null;
    try {
      settings = await service.getSettings();
      initialized = true;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load settings';
    } finally {
      loading = false;
    }
  }

  async function update(updates: Partial<UserSettings>) {
    loading = true;
    error = null;
    try {
      settings = await service.updateSettings(updates);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to update settings';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function reset() {
    loading = true;
    error = null;
    try {
      await service.resetSettings();
      settings = DEFAULT_SETTINGS;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to reset settings';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function setApiKey(provider: AIProvider, key: string) {
    loading = true;
    error = null;
    try {
      settings = await service.setApiKey(provider, key);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save API key';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function clearApiKey(provider: AIProvider) {
    loading = true;
    error = null;
    try {
      settings = await service.clearApiKey(provider);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to clear API key';
      throw e;
    } finally {
      loading = false;
    }
  }

  // Provider config setters for Azure, Bedrock, and Local
  async function setAzureConfig(config: AzureConfig) {
    loading = true;
    error = null;
    try {
      settings = await service.setAzureConfig(config);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save Azure config';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function setBedrockConfig(config: BedrockConfig) {
    loading = true;
    error = null;
    try {
      settings = await service.setBedrockConfig(config);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save Bedrock config';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function setLocalModelConfig(config: LocalModelConfig) {
    loading = true;
    error = null;
    try {
      settings = await service.setLocalModelConfig(config);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save local model config';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function clearProviderConfig(provider: 'azure' | 'bedrock' | 'local') {
    loading = true;
    error = null;
    try {
      settings = await service.clearProviderConfig(provider);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to clear provider config';
      throw e;
    } finally {
      loading = false;
    }
  }

  const isAIConfigured = $derived(
    !!(
      settings.openaiApiKey ||
      settings.geminiApiKey ||
      settings.claudeApiKey ||
      settings.azureConfig?.apiKey ||
      settings.bedrockConfig?.accessKeyId ||
      settings.localModelConfig?.endpoint
    )
  );

  const configuredProvider = $derived.by((): AIProvider | null => {
    // Check if preferred provider is configured
    if (settings.aiProvider) {
      if (isProviderConfigured(settings, settings.aiProvider)) {
        return settings.aiProvider;
      }
    }
    // Fallback to first configured provider
    if (settings.openaiApiKey) return 'openai';
    if (settings.geminiApiKey) return 'gemini';
    if (settings.claudeApiKey) return 'claude';
    if (settings.azureConfig?.apiKey && settings.azureConfig?.endpoint) return 'azure';
    if (
      settings.bedrockConfig?.accessKeyId &&
      settings.bedrockConfig?.secretAccessKey &&
      settings.bedrockConfig?.region
    )
      return 'bedrock';
    if (settings.localModelConfig?.endpoint) return 'local';
    return null;
  });

  function isProviderConfigured(s: UserSettings, provider: AIProvider): boolean {
    switch (provider) {
      case 'openai':
        return !!s.openaiApiKey;
      case 'gemini':
        return !!s.geminiApiKey;
      case 'claude':
        return !!s.claudeApiKey;
      case 'azure':
        return !!(s.azureConfig?.apiKey && s.azureConfig?.endpoint);
      case 'bedrock':
        return !!(
          s.bedrockConfig?.accessKeyId &&
          s.bedrockConfig?.secretAccessKey &&
          s.bedrockConfig?.region
        );
      case 'local':
        return !!s.localModelConfig?.endpoint;
      default:
        return false;
    }
  }

  return {
    get settings() {
      return settings;
    },
    get loading() {
      return loading;
    },
    get error() {
      return error;
    },
    get initialized() {
      return initialized;
    },
    get isAIConfigured() {
      return isAIConfigured;
    },
    get configuredProvider() {
      return configuredProvider;
    },
    load,
    update,
    reset,
    setApiKey,
    clearApiKey,
    setAzureConfig,
    setBedrockConfig,
    setLocalModelConfig,
    clearProviderConfig
  };
}

export const settingsStore = createSettingsStore();
