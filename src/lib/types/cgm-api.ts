/**
 * CGM API Integration Types
 * Task 22: Direct CGM API integration (Freestyle Libre, Dexcom)
 *
 * Defines types for connecting to CGM cloud services to fetch
 * real-time and historical glucose data.
 */

import type { BSLUnit } from './events';

/**
 * Supported CGM API providers
 */
export type CGMApiProvider = 'librelink' | 'dexcom-share' | 'nightscout';

/**
 * LibreLink API configuration
 * Uses Abbott's LibreLinkUp API for sharing glucose data
 */
export interface LibreLinkConfig {
  email: string;
  password: string;
  region?: 'us' | 'eu' | 'ae' | 'ap' | 'au' | 'ca' | 'de' | 'fr';
  patientId?: string; // For accounts following multiple patients
}

/**
 * Dexcom Share API configuration
 * Uses Dexcom Share server for real-time glucose data
 */
export interface DexcomShareConfig {
  username: string;
  password: string;
  region?: 'us' | 'ous'; // US or Outside US (International)
  accountId?: string; // Optional, auto-discovered on login
}

/**
 * Nightscout API configuration
 * Self-hosted open-source CGM data platform
 */
export interface NightscoutConfig {
  url: string; // Nightscout site URL
  apiSecret?: string; // API secret (hashed SHA1)
  token?: string; // API token (alternative to secret)
}

/**
 * Combined CGM API configuration stored in user settings
 */
export interface CGMApiConfig {
  provider: CGMApiProvider;
  libreLink?: LibreLinkConfig;
  dexcomShare?: DexcomShareConfig;
  nightscout?: NightscoutConfig;
  syncIntervalMinutes?: number; // Auto-sync interval (default: 5)
  lastSyncTimestamp?: Date;
}

/**
 * Authentication session for CGM APIs
 */
export interface CGMAuthSession {
  provider: CGMApiProvider;
  token: string;
  expiresAt?: Date;
  patientId?: string;
  accountId?: string;
}

/**
 * Single glucose reading from CGM API
 */
export interface CGMGlucoseReading {
  timestamp: Date;
  value: number;
  unit: BSLUnit;
  trend?: CGMTrendDirection;
  trendRate?: number; // Rate of change (units per minute)
  isHighAlarm?: boolean;
  isLowAlarm?: boolean;
  source: 'cgm' | 'scan' | 'finger-prick';
}

/**
 * Trend direction indicators
 */
export type CGMTrendDirection =
  | 'rising-fast' // ↑↑ >3 mg/dL/min
  | 'rising' // ↑ 2-3 mg/dL/min
  | 'rising-slow' // ↗ 1-2 mg/dL/min
  | 'stable' // → <1 mg/dL/min
  | 'falling-slow' // ↘ -1 to -2 mg/dL/min
  | 'falling' // ↓ -2 to -3 mg/dL/min
  | 'falling-fast' // ↓↓ <-3 mg/dL/min
  | 'unknown';

/**
 * Result from CGM API fetch
 */
export interface CGMFetchResult {
  provider: CGMApiProvider;
  readings: CGMGlucoseReading[];
  currentReading?: CGMGlucoseReading;
  deviceInfo?: {
    serialNumber?: string;
    modelName?: string;
    firmwareVersion?: string;
  };
  fetchedAt: Date;
  nextExpectedReading?: Date;
}

/**
 * Connection status for CGM API
 */
export interface CGMConnectionStatus {
  provider: CGMApiProvider;
  isConnected: boolean;
  lastSuccessfulSync?: Date;
  error?: string;
  patientName?: string;
  sensorExpiry?: Date;
}

/**
 * Options for fetching CGM data
 */
export interface CGMFetchOptions {
  startDate?: Date; // Fetch readings from this date
  endDate?: Date; // Fetch readings until this date
  maxCount?: number; // Maximum number of readings to fetch
  includeHistory?: boolean; // Include historical readings
}

/**
 * Interface for CGM API services
 */
export interface ICGMApiService {
  /**
   * Authenticate with the CGM service
   */
  authenticate(): Promise<CGMAuthSession>;

  /**
   * Check if currently authenticated
   */
  isAuthenticated(): boolean;

  /**
   * Get current glucose reading
   */
  getCurrentReading(): Promise<CGMGlucoseReading | null>;

  /**
   * Fetch historical readings
   */
  getReadings(options?: CGMFetchOptions): Promise<CGMFetchResult>;

  /**
   * Get connection status
   */
  getConnectionStatus(): Promise<CGMConnectionStatus>;

  /**
   * Test connection without persisting auth
   */
  testConnection(): Promise<boolean>;

  /**
   * Clear stored credentials and session
   */
  disconnect(): Promise<void>;

  /**
   * Get provider name for display
   */
  getProviderName(): string;
}

/**
 * Trend arrow Unicode characters for display
 */
export const TREND_ARROWS: Record<CGMTrendDirection, string> = {
  'rising-fast': '↑↑',
  rising: '↑',
  'rising-slow': '↗',
  stable: '→',
  'falling-slow': '↘',
  falling: '↓',
  'falling-fast': '↓↓',
  unknown: '?'
};

/**
 * Convert Dexcom trend number to direction
 */
export function dexcomTrendToDirection(trend: number): CGMTrendDirection {
  switch (trend) {
    case 1:
      return 'rising-fast';
    case 2:
      return 'rising';
    case 3:
      return 'rising-slow';
    case 4:
      return 'stable';
    case 5:
      return 'falling-slow';
    case 6:
      return 'falling';
    case 7:
      return 'falling-fast';
    default:
      return 'unknown';
  }
}

/**
 * Convert LibreLink trend to direction
 */
export function libreTrendToDirection(trend: number): CGMTrendDirection {
  // LibreLink uses similar scale: 1=rising fast, 4=stable, 7=falling fast
  return dexcomTrendToDirection(trend);
}
