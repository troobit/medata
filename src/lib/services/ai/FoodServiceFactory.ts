/**
 * Food Recognition Service Factory
 * Workstream A: AI-Powered Food Recognition
 *
 * Creates and manages AI food recognition services based on user settings.
 * Provides fallback chain for resilience.
 */

import type {
  IFoodRecognitionService,
  FoodRecognitionResult,
  RecognitionOptions
} from '$lib/types/ai';
import type { UserSettings, AIProvider } from '$lib/types/settings';
import { OpenAIFoodService } from './OpenAIFoodService';
import { GeminiFoodService } from './GeminiFoodService';
import { ClaudeFoodService } from './ClaudeFoodService';

/**
 * Creates the appropriate food service based on provider type and settings
 */
export function createFoodService(
  provider: AIProvider,
  settings: UserSettings
): IFoodRecognitionService | null {
  switch (provider) {
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
  }
  return null;
}

/**
 * Gets the preferred provider order for fallback chain
 */
function getProviderOrder(preferredProvider: AIProvider | undefined): AIProvider[] {
  const allProviders: AIProvider[] = ['openai', 'gemini', 'claude'];

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
export async function recognizeFoodWithFallback(
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
      return await service.recognizeFood(image, options);
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
