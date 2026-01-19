import { getSettingsService } from '$lib/services';
import type { UserSettings, MLProvider, AIProvider } from '$lib/types';
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

  const isMLConfigured = $derived(
    !!(
      settings.openaiApiKey ||
      settings.geminiApiKey ||
      settings.claudeApiKey ||
      (settings.foundryEndpoint && settings.foundryApiKey) ||
      settings.ollamaEndpoint
    )
  );

  // Backwards compatibility alias
  const isAIConfigured = $derived(isMLConfigured);

  const configuredProvider = $derived.by((): MLProvider | null => {
    // If explicit provider is set, check if it's configured
    if (settings.aiProvider) {
      const isConfigured = checkProviderConfigured(settings.aiProvider);
      if (isConfigured) return settings.aiProvider;
    }
    // Auto-detect first configured provider
    if (settings.openaiApiKey) return 'openai';
    if (settings.geminiApiKey) return 'gemini';
    if (settings.claudeApiKey) return 'claude';
    if (settings.foundryEndpoint && settings.foundryApiKey) return 'foundry';
    if (settings.ollamaEndpoint) return 'ollama';
    return null;
  });

  function checkProviderConfigured(provider: MLProvider): boolean {
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
    get isMLConfigured() {
      return isMLConfigured;
    },
    /** @deprecated Use isMLConfigured instead */
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
    clearApiKey
  };
}

export const settingsStore = createSettingsStore();
