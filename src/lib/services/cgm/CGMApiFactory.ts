/**
 * CGM API Service Factory
 * Task 22: Direct CGM API integration
 *
 * Creates and manages CGM API services based on user configuration.
 */

import type { ICGMApiService, CGMApiConfig, CGMApiProvider } from '$lib/types/cgm-api';
import { LibreLinkApiService } from './LibreLinkApiService';
import { DexcomShareApiService } from './DexcomShareApiService';

/**
 * Creates the appropriate CGM API service based on provider type
 */
export function createCGMApiService(config: CGMApiConfig): ICGMApiService | null {
  switch (config.provider) {
    case 'librelink':
      if (config.libreLink?.email && config.libreLink?.password) {
        return new LibreLinkApiService(config.libreLink);
      }
      break;
    case 'dexcom-share':
      if (config.dexcomShare?.username && config.dexcomShare?.password) {
        return new DexcomShareApiService(config.dexcomShare);
      }
      break;
    case 'nightscout':
      // Nightscout support can be added in future
      console.warn('Nightscout API not yet implemented');
      break;
  }
  return null;
}

/**
 * Checks if CGM API is configured
 */
export function isCGMApiConfigured(config: CGMApiConfig | undefined): boolean {
  if (!config) return false;

  switch (config.provider) {
    case 'librelink':
      return !!(config.libreLink?.email && config.libreLink?.password);
    case 'dexcom-share':
      return !!(config.dexcomShare?.username && config.dexcomShare?.password);
    case 'nightscout':
      return !!config.nightscout?.url;
    default:
      return false;
  }
}

/**
 * Get display name for CGM provider
 */
export function getCGMProviderName(provider: CGMApiProvider): string {
  const names: Record<CGMApiProvider, string> = {
    librelink: 'Freestyle Libre (LibreLinkUp)',
    'dexcom-share': 'Dexcom Share',
    nightscout: 'Nightscout'
  };
  return names[provider] || provider;
}

/**
 * Available CGM providers
 */
export const CGM_PROVIDERS: Array<{ value: CGMApiProvider; label: string; description: string }> = [
  {
    value: 'librelink',
    label: 'Freestyle Libre',
    description: 'Connect via LibreLinkUp (requires sharing enabled)'
  },
  {
    value: 'dexcom-share',
    label: 'Dexcom',
    description: 'Connect via Dexcom Share (requires sharing enabled)'
  },
  {
    value: 'nightscout',
    label: 'Nightscout',
    description: 'Connect to self-hosted Nightscout instance'
  }
];
