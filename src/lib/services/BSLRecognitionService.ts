import type { BSLUnit } from '$lib/types';
import type { ExtractedBSLReading, BSLExtractionResult } from '$lib/types/vision';
import { VisionService, getVisionService, VisionServiceError } from './VisionService';

const EXTRACTION_PROMPT = `Analyze this screenshot from a continuous glucose monitor (CGM) app like Freestyle Libre, Dexcom, or similar.

Extract ALL visible blood sugar/glucose readings from the image. For each reading, provide:
1. The glucose value (number)
2. The unit (either "mmol/L" or "mg/dL")
3. The timestamp if visible (as ISO 8601 format, e.g., "2024-01-15T14:30:00")
4. Your confidence in the reading (0.0 to 1.0)

If you cannot determine the exact timestamp, estimate based on context (e.g., if the app shows "2 hours ago" and current time context).

IMPORTANT:
- If the unit is not explicitly shown, infer it from the value range (mmol/L typically 2-30, mg/dL typically 40-500)
- Extract ALL readings visible, including historical data points if shown in a graph or list
- If this is not a CGM/glucose screenshot, return an empty readings array

Respond ONLY with valid JSON in this exact format:
{
  "readings": [
    {
      "value": 7.2,
      "unit": "mmol/L",
      "timestamp": "2024-01-15T14:30:00",
      "confidence": 0.95,
      "rawText": "7.2 mmol/L"
    }
  ],
  "source": "libre"
}

The "source" field should be: "libre", "dexcom", "medtronic", "omnipod", or "unknown" based on the app interface.`;

/**
 * Service for extracting BSL readings from screenshots
 */
export class BSLRecognitionService {
  constructor(private visionService: VisionService = getVisionService()) {}

  /**
   * Extract BSL readings from a screenshot
   * @param imageBase64 Base64-encoded image data
   * @returns Extraction result with readings array
   */
  async extractReadings(imageBase64: string): Promise<BSLExtractionResult> {
    try {
      const response = await this.visionService.analyzeImage(imageBase64, EXTRACTION_PROMPT);
      return this.parseResponse(response);
    } catch (error) {
      if (error instanceof VisionServiceError) {
        return {
          readings: [],
          error: error.message
        };
      }
      return {
        readings: [],
        error: error instanceof Error ? error.message : 'Failed to analyze image'
      };
    }
  }

  /**
   * Parse the API response into structured data
   */
  private parseResponse(response: string): BSLExtractionResult {
    try {
      // Extract JSON from potential markdown code blocks
      const jsonMatch =
        response.match(/```(?:json)?\s*([\s\S]*?)```/) || response.match(/\{[\s\S]*\}/);

      const jsonStr = jsonMatch?.[1] || jsonMatch?.[0] || response;
      const parsed = JSON.parse(jsonStr.trim());

      if (!parsed.readings || !Array.isArray(parsed.readings)) {
        return {
          readings: [],
          error: 'Invalid response format: no readings array'
        };
      }

      const readings: ExtractedBSLReading[] = parsed.readings
        .map((r: Record<string, unknown>) => this.normalizeReading(r))
        .filter((r: ExtractedBSLReading | null): r is ExtractedBSLReading => r !== null);

      return {
        readings,
        imageMetadata: {
          source: parsed.source || 'unknown'
        }
      };
    } catch {
      return {
        readings: [],
        error: 'Failed to parse API response'
      };
    }
  }

  /**
   * Normalise and validate a single reading
   */
  private normalizeReading(raw: Record<string, unknown>): ExtractedBSLReading | null {
    const value = typeof raw.value === 'number' ? raw.value : parseFloat(String(raw.value));

    if (isNaN(value) || value <= 0) {
      return null;
    }

    // Normalise unit
    let unit: BSLUnit = 'mmol/L';
    if (typeof raw.unit === 'string') {
      const unitLower = raw.unit.toLowerCase();
      if (unitLower.includes('mg') || unitLower === 'mg/dl') {
        unit = 'mg/dL';
      }
    } else {
      // Infer unit from value range
      unit = value > 35 ? 'mg/dL' : 'mmol/L';
    }

    // Validate value ranges
    if (unit === 'mmol/L' && (value < 1 || value > 35)) {
      return null;
    }
    if (unit === 'mg/dL' && (value < 20 || value > 600)) {
      return null;
    }

    // Parse timestamp
    let timestamp: Date;
    if (raw.timestamp) {
      const parsed = new Date(String(raw.timestamp));
      timestamp = isNaN(parsed.getTime()) ? new Date() : parsed;
    } else {
      timestamp = new Date();
    }

    // Confidence score
    const confidence =
      typeof raw.confidence === 'number' ? Math.max(0, Math.min(1, raw.confidence)) : 0.8;

    return {
      value,
      unit,
      timestamp,
      confidence,
      rawText: typeof raw.rawText === 'string' ? raw.rawText : undefined
    };
  }

  /**
   * Check if the vision service is configured
   */
  isConfigured(): boolean {
    return this.visionService.isConfigured();
  }
}

// Singleton instance
let bslRecognitionService: BSLRecognitionService | null = null;

export function getBSLRecognitionService(): BSLRecognitionService {
  if (!bslRecognitionService) {
    bslRecognitionService = new BSLRecognitionService();
  }
  return bslRecognitionService;
}
