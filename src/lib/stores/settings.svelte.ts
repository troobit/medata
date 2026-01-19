import { getSettingsService } from '$lib/services';
import type { UserSettings, AIProvider } from '$lib/types';
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

  const isAIConfigured = $derived(
    !!(settings.openaiApiKey || settings.geminiApiKey || settings.claudeApiKey)
  );

  const configuredProvider = $derived.by((): AIProvider | null => {
    if (settings.aiProvider) {
      const keyMap: Record<AIProvider, keyof UserSettings> = {
        openai: 'openaiApiKey',
        gemini: 'geminiApiKey',
        claude: 'claudeApiKey'
      };
      if (settings[keyMap[settings.aiProvider]]) return settings.aiProvider;
    }
    if (settings.openaiApiKey) return 'openai';
    if (settings.geminiApiKey) return 'gemini';
    if (settings.claudeApiKey) return 'claude';
    return null;
  });

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
    clearApiKey
  };
}

export const settingsStore = createSettingsStore();
