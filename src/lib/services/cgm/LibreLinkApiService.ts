/**
 * LibreLink API Service
 * Task 22: Direct CGM API integration - Freestyle Libre
 *
 * Connects to Abbott's LibreLinkUp API to fetch glucose data
 * from Freestyle Libre sensors (Libre 2, Libre 3).
 *
 * Note: This uses the unofficial LibreLinkUp API which may change.
 * Users must have LibreLinkUp sharing enabled in their Libre app.
 */

import type {
  ICGMApiService,
  CGMAuthSession,
  CGMGlucoseReading,
  CGMFetchResult,
  CGMConnectionStatus,
  CGMFetchOptions,
  LibreLinkConfig
} from '$lib/types/cgm-api';
import { libreTrendToDirection } from '$lib/types/cgm-api';
import type { BSLUnit } from '$lib/types/events';

// LibreLinkUp API endpoints by region
const LIBRE_API_ENDPOINTS: Record<string, string> = {
  us: 'https://api-us.libreview.io',
  eu: 'https://api-eu.libreview.io',
  ae: 'https://api-ae.libreview.io',
  ap: 'https://api-ap.libreview.io',
  au: 'https://api-au.libreview.io',
  ca: 'https://api-ca.libreview.io',
  de: 'https://api-de.libreview.io',
  fr: 'https://api-fr.libreview.io'
};

interface LibreLoginResponse {
  data: {
    authTicket: {
      token: string;
      expires: number;
    };
    user: {
      id: string;
      firstName: string;
      lastName: string;
    };
  };
  status: number;
}

interface LibreConnectionsResponse {
  data: Array<{
    patientId: string;
    firstName: string;
    lastName: string;
    glucoseMeasurement?: LibreGlucoseMeasurement;
    sensor?: {
      sn: string;
      a: number; // sensor activation timestamp
      pt: number; // sensor type
    };
  }>;
  status: number;
}

interface LibreGlucoseMeasurement {
  Value: number;
  Timestamp: string;
  TrendArrow: number;
  MeasurementColor: number;
  isHigh: boolean;
  isLow: boolean;
}

interface LibreGraphResponse {
  data: {
    graphData: Array<{
      Value: number;
      Timestamp: string;
    }>;
  };
  status: number;
}

export class LibreLinkApiService implements ICGMApiService {
  private config: LibreLinkConfig;
  private session: CGMAuthSession | null = null;
  private baseUrl: string;

  constructor(config: LibreLinkConfig) {
    this.config = config;
    const region = config.region || 'us';
    this.baseUrl = LIBRE_API_ENDPOINTS[region] || LIBRE_API_ENDPOINTS.us;
  }

  async authenticate(): Promise<CGMAuthSession> {
    const response = await fetch(`${this.baseUrl}/llu/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        product: 'llu.android',
        version: '4.7.0'
      },
      body: JSON.stringify({
        email: this.config.email,
        password: this.config.password
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`LibreLink authentication failed: ${response.status} - ${errorText}`);
    }

    const data: LibreLoginResponse = await response.json();

    if (data.status !== 0) {
      throw new Error(
        'LibreLink login failed. Check credentials and ensure LibreLinkUp sharing is enabled.'
      );
    }

    this.session = {
      provider: 'librelink',
      token: data.data.authTicket.token,
      expiresAt: new Date(data.data.authTicket.expires * 1000),
      accountId: data.data.user.id
    };

    // If no patient ID specified, fetch connections to find patient
    if (!this.config.patientId) {
      await this.fetchConnections();
    }

    return this.session;
  }

  private async fetchConnections(): Promise<void> {
    if (!this.session) {
      throw new Error('Not authenticated');
    }

    const response = await fetch(`${this.baseUrl}/llu/connections`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.session.token}`,
        product: 'llu.android',
        version: '4.7.0'
      }
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch connections: ${response.status}`);
    }

    const data: LibreConnectionsResponse = await response.json();

    if (data.data.length === 0) {
      throw new Error('No connected patients found. Enable LibreLinkUp sharing in your Libre app.');
    }

    // Use first patient if not specified
    this.session.patientId = data.data[0].patientId;
  }

  isAuthenticated(): boolean {
    if (!this.session) return false;
    if (this.session.expiresAt && this.session.expiresAt < new Date()) {
      return false;
    }
    return true;
  }

  async getCurrentReading(): Promise<CGMGlucoseReading | null> {
    if (!this.isAuthenticated()) {
      await this.authenticate();
    }

    const response = await fetch(`${this.baseUrl}/llu/connections`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.session!.token}`,
        product: 'llu.android',
        version: '4.7.0'
      }
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch current reading: ${response.status}`);
    }

    const data: LibreConnectionsResponse = await response.json();

    // Find the patient's data
    const patientData = this.session?.patientId
      ? data.data.find((p) => p.patientId === this.session?.patientId)
      : data.data[0];

    if (!patientData?.glucoseMeasurement) {
      return null;
    }

    const measurement = patientData.glucoseMeasurement;

    return {
      timestamp: new Date(measurement.Timestamp),
      value: this.convertToMmol(measurement.Value),
      unit: 'mmol/L' as BSLUnit,
      trend: libreTrendToDirection(measurement.TrendArrow),
      isHighAlarm: measurement.isHigh,
      isLowAlarm: measurement.isLow,
      source: 'cgm'
    };
  }

  async getReadings(options?: CGMFetchOptions): Promise<CGMFetchResult> {
    if (!this.isAuthenticated()) {
      await this.authenticate();
    }

    // LibreLink API returns limited historical data via graph endpoint
    const patientId = this.session?.patientId || this.config.patientId;
    if (!patientId) {
      throw new Error('No patient ID available');
    }

    const response = await fetch(`${this.baseUrl}/llu/connections/${patientId}/graph`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.session!.token}`,
        product: 'llu.android',
        version: '4.7.0'
      }
    });

    if (!response.ok) {
      throw new Error(`Failed to fetch historical readings: ${response.status}`);
    }

    const data: LibreGraphResponse = await response.json();

    let readings: CGMGlucoseReading[] = data.data.graphData.map((point) => ({
      timestamp: new Date(point.Timestamp),
      value: this.convertToMmol(point.Value),
      unit: 'mmol/L' as BSLUnit,
      source: 'cgm' as const
    }));

    // Apply date filters if provided
    if (options?.startDate) {
      readings = readings.filter((r) => r.timestamp >= options.startDate!);
    }
    if (options?.endDate) {
      readings = readings.filter((r) => r.timestamp <= options.endDate!);
    }
    if (options?.maxCount) {
      readings = readings.slice(-options.maxCount);
    }

    // Sort by timestamp
    readings.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

    // Get current reading
    const currentReading = await this.getCurrentReading();

    return {
      provider: 'librelink',
      readings,
      currentReading: currentReading || undefined,
      fetchedAt: new Date()
    };
  }

  async getConnectionStatus(): Promise<CGMConnectionStatus> {
    try {
      if (!this.isAuthenticated()) {
        await this.authenticate();
      }

      const response = await fetch(`${this.baseUrl}/llu/connections`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.session!.token}`,
          product: 'llu.android',
          version: '4.7.0'
        }
      });

      if (!response.ok) {
        throw new Error(`Connection check failed: ${response.status}`);
      }

      const data: LibreConnectionsResponse = await response.json();
      const patient = this.session?.patientId
        ? data.data.find((p) => p.patientId === this.session?.patientId)
        : data.data[0];

      return {
        provider: 'librelink',
        isConnected: true,
        lastSuccessfulSync: new Date(),
        patientName: patient ? `${patient.firstName} ${patient.lastName}` : undefined,
        sensorExpiry: patient?.sensor
          ? new Date(patient.sensor.a * 1000 + 14 * 24 * 60 * 60 * 1000) // 14 days from activation
          : undefined
      };
    } catch (error) {
      return {
        provider: 'librelink',
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
    return 'Freestyle Libre (LibreLinkUp)';
  }

  /**
   * Convert mg/dL to mmol/L if needed
   * LibreLink API returns mg/dL in most regions
   */
  private convertToMmol(mgdl: number): number {
    return Math.round((mgdl / 18.0182) * 10) / 10;
  }
}

export function createLibreLinkApiService(config: LibreLinkConfig): LibreLinkApiService {
  return new LibreLinkApiService(config);
}
