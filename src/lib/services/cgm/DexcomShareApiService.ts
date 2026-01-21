/**
 * Dexcom Share API Service
 * Task 22: Direct CGM API integration - Dexcom
 *
 * Connects to Dexcom Share server to fetch glucose data
 * from Dexcom G6/G7 sensors.
 *
 * Note: Users must have Dexcom Share enabled in their Dexcom app
 * and have set up followers.
 */

import type {
  ICGMApiService,
  CGMAuthSession,
  CGMGlucoseReading,
  CGMFetchResult,
  CGMConnectionStatus,
  CGMFetchOptions,
  DexcomShareConfig
} from '$lib/types/cgm-api';
import { dexcomTrendToDirection } from '$lib/types/cgm-api';
import type { BSLUnit } from '$lib/types/events';

// Dexcom Share API endpoints
const DEXCOM_ENDPOINTS = {
  us: 'https://share2.dexcom.com/ShareWebServices/Services',
  ous: 'https://shareous1.dexcom.com/ShareWebServices/Services'
};

const DEXCOM_APPLICATION_ID = 'd89443d2-327c-4a6f-89e5-496bbb0317db';

interface DexcomLoginResponse {
  // Returns session ID string directly
  SessionId: string;
}

interface DexcomReadingsResponse {
  // Array of glucose readings
  ST: string; // System time
  DT: string; // Display time (local)
  WT: string; // Wall time
  Value: number; // mg/dL
  Trend: number; // Trend direction (1-7)
}

export class DexcomShareApiService implements ICGMApiService {
  private config: DexcomShareConfig;
  private session: CGMAuthSession | null = null;
  private baseUrl: string;

  constructor(config: DexcomShareConfig) {
    this.config = config;
    const region = config.region || 'us';
    this.baseUrl = DEXCOM_ENDPOINTS[region] || DEXCOM_ENDPOINTS.us;
  }

  async authenticate(): Promise<CGMAuthSession> {
    // Step 1: Get account ID
    const accountId = await this.getAccountId();

    // Step 2: Login to get session
    const loginResponse = await fetch(`${this.baseUrl}/General/LoginPublisherAccountById`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json'
      },
      body: JSON.stringify({
        accountId: accountId,
        password: this.config.password,
        applicationId: DEXCOM_APPLICATION_ID
      })
    });

    if (!loginResponse.ok) {
      const errorText = await loginResponse.text();
      throw new Error(`Dexcom login failed: ${loginResponse.status} - ${errorText}`);
    }

    const sessionId = await loginResponse.json();

    if (!sessionId || typeof sessionId !== 'string') {
      throw new Error('Dexcom login failed: Invalid session response');
    }

    this.session = {
      provider: 'dexcom-share',
      token: sessionId.replace(/"/g, ''), // Remove quotes if present
      accountId: accountId
    };

    return this.session;
  }

  private async getAccountId(): Promise<string> {
    if (this.config.accountId) {
      return this.config.accountId;
    }

    const response = await fetch(`${this.baseUrl}/General/AuthenticatePublisherAccount`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json'
      },
      body: JSON.stringify({
        accountName: this.config.username,
        password: this.config.password,
        applicationId: DEXCOM_APPLICATION_ID
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Dexcom authentication failed: ${response.status} - ${errorText}`);
    }

    const accountId = await response.json();
    return accountId.replace(/"/g, '');
  }

  isAuthenticated(): boolean {
    return !!this.session?.token;
  }

  async getCurrentReading(): Promise<CGMGlucoseReading | null> {
    const result = await this.getReadings({ maxCount: 1 });
    return result.currentReading || null;
  }

  async getReadings(options?: CGMFetchOptions): Promise<CGMFetchResult> {
    if (!this.isAuthenticated()) {
      await this.authenticate();
    }

    const maxCount = options?.maxCount || 288; // Default to 24 hours of readings (5 min intervals)
    const minutes = options?.startDate
      ? Math.ceil((Date.now() - options.startDate.getTime()) / 60000)
      : 1440; // Default 24 hours

    const response = await fetch(
      `${this.baseUrl}/Publisher/ReadPublisherLatestGlucoseValues?` +
        `sessionId=${this.session!.token}&minutes=${minutes}&maxCount=${maxCount}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json'
        }
      }
    );

    if (!response.ok) {
      // Session may have expired, try re-authenticating
      if (response.status === 500) {
        this.session = null;
        await this.authenticate();
        return this.getReadings(options);
      }
      throw new Error(`Failed to fetch Dexcom readings: ${response.status}`);
    }

    const data: DexcomReadingsResponse[] = await response.json();

    const readings: CGMGlucoseReading[] = data.map((reading) => ({
      timestamp: this.parseWallTime(reading.WT),
      value: this.convertToMmol(reading.Value),
      unit: 'mmol/L' as BSLUnit,
      trend: dexcomTrendToDirection(reading.Trend),
      source: 'cgm' as const
    }));

    // Apply date filters if provided
    let filteredReadings = readings;
    if (options?.startDate) {
      filteredReadings = filteredReadings.filter((r) => r.timestamp >= options.startDate!);
    }
    if (options?.endDate) {
      filteredReadings = filteredReadings.filter((r) => r.timestamp <= options.endDate!);
    }

    // Sort by timestamp (newest first in API response, so reverse)
    filteredReadings.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

    // Current reading is the most recent
    const currentReading =
      filteredReadings.length > 0 ? filteredReadings[filteredReadings.length - 1] : undefined;

    return {
      provider: 'dexcom-share',
      readings: filteredReadings,
      currentReading,
      fetchedAt: new Date()
    };
  }

  async getConnectionStatus(): Promise<CGMConnectionStatus> {
    try {
      if (!this.isAuthenticated()) {
        await this.authenticate();
      }

      // Try to fetch a single reading to verify connection
      const result = await this.getReadings({ maxCount: 1 });

      return {
        provider: 'dexcom-share',
        isConnected: true,
        lastSuccessfulSync: new Date()
      };
    } catch (error) {
      return {
        provider: 'dexcom-share',
        isConnected: false,
        error: error instanceof Error ? error.message : 'Connection failed'
      };
    }
  }

  async testConnection(): Promise<boolean> {
    try {
      await this.authenticate();
      return true;
    } catch {
      return false;
    }
  }

  async disconnect(): Promise<void> {
    this.session = null;
  }

  getProviderName(): string {
    return 'Dexcom Share';
  }

  /**
   * Parse Dexcom's wall time format: /Date(1234567890000)/
   */
  private parseWallTime(wallTime: string): Date {
    const match = wallTime.match(/\/Date\((\d+)\)\//);
    if (match) {
      return new Date(parseInt(match[1], 10));
    }
    return new Date(wallTime);
  }

  /**
   * Convert mg/dL to mmol/L
   */
  private convertToMmol(mgdl: number): number {
    return Math.round((mgdl / 18.0182) * 10) / 10;
  }
}

export function createDexcomShareApiService(config: DexcomShareConfig): DexcomShareApiService {
  return new DexcomShareApiService(config);
}
