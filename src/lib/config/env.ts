/**
 * Environment Configuration
 *
 * Reads configuration from environment variables (via Vite's import.meta.env).
 * These values serve as defaults that can be overridden by user settings in localStorage.
 */

import type {
  AIProvider,
  AzureConfig,
  BedrockConfig,
  LocalModelConfig,
  UserSettings
} from '$lib/types/settings';
import { ENV_VAR_NAMES } from '$lib/types/settings';

/**
 * Gets an environment variable value, returning undefined if empty or not set
 */
function getEnvVar(key: string): string | undefined {
  // Check if we're in a browser environment with Vite
  if (typeof import.meta !== 'undefined' && import.meta.env) {
    const value = import.meta.env[key];
    return value && value.trim() !== '' ? value.trim() : undefined;
  }
  return undefined;
}

/**
 * Gets the AI provider from environment, with validation
 */
function getEnvProvider(): AIProvider | undefined {
  const value = getEnvVar(ENV_VAR_NAMES.AI_PROVIDER);
  if (!value) return undefined;

  const validProviders: AIProvider[] = ['openai', 'gemini', 'claude', 'azure', 'bedrock', 'local'];
  if (validProviders.includes(value as AIProvider)) {
    return value as AIProvider;
  }

  console.warn(`Invalid AI_PROVIDER value: ${value}. Valid options: ${validProviders.join(', ')}`);
  return undefined;
}

/**
 * Gets Azure OpenAI configuration from environment
 */
function getEnvAzureConfig(): AzureConfig | undefined {
  const apiKey = getEnvVar(ENV_VAR_NAMES.AZURE_OPENAI_API_KEY);
  const endpoint = getEnvVar(ENV_VAR_NAMES.AZURE_OPENAI_ENDPOINT);

  // At minimum need API key and endpoint
  if (!apiKey || !endpoint) return undefined;

  return {
    apiKey,
    endpoint,
    deploymentName: getEnvVar(ENV_VAR_NAMES.AZURE_OPENAI_DEPLOYMENT),
    apiVersion: getEnvVar(ENV_VAR_NAMES.AZURE_OPENAI_API_VERSION) || '2024-02-15-preview'
  };
}

/**
 * Gets Amazon Bedrock configuration from environment
 */
function getEnvBedrockConfig(): BedrockConfig | undefined {
  const accessKeyId = getEnvVar(ENV_VAR_NAMES.AWS_ACCESS_KEY_ID);
  const secretAccessKey = getEnvVar(ENV_VAR_NAMES.AWS_SECRET_ACCESS_KEY);
  const region = getEnvVar(ENV_VAR_NAMES.AWS_REGION);

  // Need all three for Bedrock
  if (!accessKeyId || !secretAccessKey || !region) return undefined;

  return {
    accessKeyId,
    secretAccessKey,
    region,
    modelId: getEnvVar(ENV_VAR_NAMES.BEDROCK_MODEL_ID)
  };
}

/**
 * Gets local model configuration from environment
 */
function getEnvLocalConfig(): LocalModelConfig | undefined {
  const endpoint = getEnvVar(ENV_VAR_NAMES.LOCAL_MODEL_ENDPOINT);

  // Need at minimum an endpoint
  if (!endpoint) return undefined;

  const typeValue = getEnvVar(ENV_VAR_NAMES.LOCAL_MODEL_TYPE);
  let type: LocalModelConfig['type'] = 'ollama'; // default

  if (typeValue === 'lmstudio' || typeValue === 'openai-compatible') {
    type = typeValue;
  }

  return {
    endpoint,
    modelName: getEnvVar(ENV_VAR_NAMES.LOCAL_MODEL_NAME),
    type
  };
}

/**
 * Gets settings derived from environment variables.
 * Returns a partial UserSettings object with only env-configured values.
 */
export function getEnvSettings(): Partial<UserSettings> {
  const settings: Partial<UserSettings> = {};

  // Direct API keys
  const openaiApiKey = getEnvVar(ENV_VAR_NAMES.OPENAI_API_KEY);
  if (openaiApiKey) settings.openaiApiKey = openaiApiKey;

  const geminiApiKey = getEnvVar(ENV_VAR_NAMES.GEMINI_API_KEY);
  if (geminiApiKey) settings.geminiApiKey = geminiApiKey;

  const claudeApiKey = getEnvVar(ENV_VAR_NAMES.CLAUDE_API_KEY);
  if (claudeApiKey) settings.claudeApiKey = claudeApiKey;

  // Azure config
  const azureConfig = getEnvAzureConfig();
  if (azureConfig) settings.azureConfig = azureConfig;

  // Bedrock config
  const bedrockConfig = getEnvBedrockConfig();
  if (bedrockConfig) settings.bedrockConfig = bedrockConfig;

  // Local model config
  const localModelConfig = getEnvLocalConfig();
  if (localModelConfig) settings.localModelConfig = localModelConfig;

  // Default provider (only set if specified)
  const aiProvider = getEnvProvider();
  if (aiProvider) settings.aiProvider = aiProvider;

  return settings;
}

/**
 * Merges environment settings with user settings.
 * User settings take precedence over environment settings.
 */
export function mergeWithEnvSettings(userSettings: UserSettings): UserSettings {
  const envSettings = getEnvSettings();

  // Start with env settings as base, overlay user settings
  return {
    ...userSettings,
    // Only use env values if user hasn't set them
    openaiApiKey: userSettings.openaiApiKey || envSettings.openaiApiKey,
    geminiApiKey: userSettings.geminiApiKey || envSettings.geminiApiKey,
    claudeApiKey: userSettings.claudeApiKey || envSettings.claudeApiKey,
    azureConfig: userSettings.azureConfig || envSettings.azureConfig,
    bedrockConfig: userSettings.bedrockConfig || envSettings.bedrockConfig,
    localModelConfig: userSettings.localModelConfig || envSettings.localModelConfig,
    // Use user's provider preference if set, otherwise fall back to env
    aiProvider: userSettings.aiProvider || envSettings.aiProvider
  };
}

/**
 * Checks if any AI provider is configured via environment variables
 */
export function hasEnvAIConfig(): boolean {
  const envSettings = getEnvSettings();
  return !!(
    envSettings.openaiApiKey ||
    envSettings.geminiApiKey ||
    envSettings.claudeApiKey ||
    envSettings.azureConfig ||
    envSettings.bedrockConfig ||
    envSettings.localModelConfig
  );
}
