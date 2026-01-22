/**
 * Food Recognition Service Factory
 * Workstream A: AI-Powered Food Recognition
 *
 * Creates and manages AI food recognition services based on user settings.
 * Provides fallback chain for resilience.
 *
 * Supported providers (in priority order):
 * - Azure AI Foundry (v1 API - recommended for Azure users)
 * - OpenAI (GPT-4 Vision)
 * - Google Gemini
 * - Anthropic Claude
 * - Azure OpenAI Service (classic)
 * - Amazon Bedrock
 * - Local models (Ollama, LM Studio)
 */

import type {
  IFoodRecognitionService,
  FoodRecognitionResult,
  RecognitionOptions
} from '$lib/types/ai';
import type { UserSettings, AIProvider } from '$lib/types/settings';
import { AzureFoundryFoodService } from './AzureFoundryFoodService';
import { OpenAIFoodService } from './OpenAIFoodService';
import { GeminiFoodService } from './GeminiFoodService';
import { ClaudeFoodService } from './ClaudeFoodService';
import { AzureFoodService } from './AzureFoodService';
import { BedrockFoodService } from './BedrockFoodService';
import { LocalFoodService } from './LocalFoodService';

/**
 * Creates the appropriate food service based on provider type and settings
 */
export function createFoodService(
  provider: AIProvider,
  settings: UserSettings
): IFoodRecognitionService | null {
  switch (provider) {
    case 'foundry':
      if (settings.foundryConfig?.apiKey && settings.foundryConfig?.endpoint) {
        return new AzureFoundryFoodService(settings.foundryConfig);
      }
      break;
    case 'openai':
      if (settings.openaiApiKey) {
        return new OpenAIFoodService(settings.openaiApiKey);
      }
      break;
    case 'gemini':
      if (settings.geminiApiKey) {
        return new GeminiFoodService(settings.geminiApiKey);
      }
      break;
    case 'claude':
      if (settings.claudeApiKey) {
        return new ClaudeFoodService(settings.claudeApiKey);
      }
      break;
    case 'azure':
      if (settings.azureConfig?.apiKey && settings.azureConfig?.endpoint) {
        return new AzureFoodService(settings.azureConfig);
      }
      break;
    case 'bedrock':
      if (
        settings.bedrockConfig?.accessKeyId &&
        settings.bedrockConfig?.secretAccessKey &&
        settings.bedrockConfig?.region
      ) {
        return new BedrockFoodService(settings.bedrockConfig);
      }
      break;
    case 'local':
      if (settings.localModelConfig?.endpoint) {
        return new LocalFoodService(settings.localModelConfig);
      }
      break;
  }
  return null;
}

/**
 * Gets the preferred provider order for fallback chain
 * Note: 'foundry' (Azure AI Foundry) is first as the primary Azure provider
 */
function getProviderOrder(preferredProvider: AIProvider | undefined): AIProvider[] {
  const allProviders: AIProvider[] = [
    'foundry',
    'openai',
    'gemini',
    'claude',
    'azure',
    'bedrock',
    'local'
  ];

  if (!preferredProvider) {
    return allProviders;
  }

  // Put preferred provider first, then the rest
  return [preferredProvider, ...allProviders.filter((p) => p !== preferredProvider)];
}

/**
 * Gets the first available food service based on settings
 */
export function getFoodService(settings: UserSettings): IFoodRecognitionService | null {
  const providerOrder = getProviderOrder(settings.aiProvider);

  for (const provider of providerOrder) {
    const service = createFoodService(provider, settings);
    if (service?.isConfigured()) {
      return service;
    }
  }

  return null;
}

/**
 * Gets all configured food services for fallback
 */
export function getAllConfiguredServices(settings: UserSettings): IFoodRecognitionService[] {
  const providerOrder = getProviderOrder(settings.aiProvider);
  const services: IFoodRecognitionService[] = [];

  for (const provider of providerOrder) {
    const service = createFoodService(provider, settings);
    if (service?.isConfigured()) {
      services.push(service);
    }
  }

  return services;
}

/**
 * Attempts food recognition with automatic fallback to next provider on failure
 */
export async function RecogniseFoodWithFallback(
  image: Blob,
  settings: UserSettings,
  options?: RecognitionOptions
): Promise<FoodRecognitionResult> {
  const services = getAllConfiguredServices(settings);

  if (services.length === 0) {
    throw new Error('No AI providers configured. Please add an API key in Settings.');
  }

  let lastError: Error | null = null;

  for (const service of services) {
    try {
      return await service.RecogniseFood(image, options);
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      console.warn(`${service.getProviderName()} failed, trying next provider:`, lastError.message);
    }
  }

  throw lastError || new Error('All AI providers failed');
}

/**
 * Checks if any AI provider is configured
 */
export function isAnyProviderConfigured(settings: UserSettings): boolean {
  return getAllConfiguredServices(settings).length > 0;
}

/**
 * Gets the name of the currently configured primary provider
 */
export function getPrimaryProviderName(settings: UserSettings): string | null {
  const service = getFoodService(settings);
  return service?.getProviderName() ?? null;
}
