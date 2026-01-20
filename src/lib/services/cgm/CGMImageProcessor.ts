/**
 * Workstream B: CGM Graph Image Processor
 *
 * Main service for extracting BSL time-series data from CGM app screenshots.
 * Supports both ML-assisted extraction via cloud vision APIs and local
 * computer vision algorithms for offline/privacy-first extraction.
 */

import type {
  ICGMImageService,
  CGMDeviceType,
  CGMExtractionResult,
  CGMExtractionOptions,
  AxisRanges,
  GraphRegion,
  ExtractedDataPoint
} from '$lib/types/cgm';
import type { BSLUnit } from '$lib/types/events';
import type { MLProvider, UserSettings } from '$lib/types/settings';
import { LocalCurveExtractor } from './LocalCurveExtractor';
import { LibreGraphParser } from './LibreGraphParser';
import { DexcomGraphParser } from './DexcomGraphParser';

/**
 * Prompt for CGM graph extraction via vision API
 */
const CGM_EXTRACTION_PROMPT = `Analyze this CGM (Continuous Glucose Monitor) graph image and extract the blood sugar readings.

Instructions:
1. Identify the graph type (Freestyle Libre, Dexcom, Medtronic, or other)
2. Detect the axis ranges:
   - Time axis: start and end times
   - Y-axis: minimum and maximum BSL values and unit (mmol/L or mg/dL)
3. Trace the glucose curve and extract data points at regular intervals (approximately every 5 minutes)
4. For each point, estimate the BSL value based on its vertical position

Return a JSON object with this exact structure:
{
  "deviceType": "freestyle-libre" | "dexcom" | "medtronic" | "generic",
  "axisRanges": {
    "timeStartHours": <number of hours from midnight for start>,
    "timeEndHours": <number of hours from midnight for end>,
    "bslMin": <number>,
    "bslMax": <number>,
    "unit": "mmol/L" | "mg/dL"
  },
  "dataPoints": [
    {"minutesFromStart": <number>, "value": <BSL reading>},
    ...
  ],
  "graphRegion": {"x": 0, "y": 0, "width": 100, "height": 100},
  "warnings": ["<any issues or low confidence areas>"]
}

Be precise with values. If you cannot determine exact values, estimate based on visual position relative to axis labels and gridlines.`;

interface MLExtractionResponse {
  deviceType: CGMDeviceType;
  axisRanges: {
    timeStartHours: number;
    timeEndHours: number;
    bslMin: number;
    bslMax: number;
    unit: BSLUnit;
  };
  dataPoints: Array<{ minutesFromStart: number; value: number }>;
  graphRegion: GraphRegion;
  warnings?: string[];
}

/**
 * Extended options for CGM extraction with local fallback support
 */
export interface ExtendedCGMExtractionOptions extends CGMExtractionOptions {
  /** Force use of local extraction even if ML is available */
  useLocalExtraction?: boolean;
  /** Preferred extraction method: 'ml' | 'local' | 'auto' (default: 'auto') */
  preferredMethod?: 'ml' | 'local' | 'auto';
}

/**
 * CGMImageProcessor - Extracts BSL data from CGM screenshots
 *
 * Supports two extraction methods:
 * 1. ML-assisted extraction via cloud vision APIs (higher accuracy)
 * 2. Local computer vision extraction (offline, privacy-first)
 *
 * By default, uses ML when configured and falls back to local extraction.
 */
export class CGMImageProcessor implements ICGMImageService {
  private settings: UserSettings;
  private localExtractor: LocalCurveExtractor | null = null;
  private libreParser: LibreGraphParser | null = null;
  private dexcomParser: DexcomGraphParser | null = null;

  constructor(settings: UserSettings) {
    this.settings = settings;
  }

  /**
   * Get or create local curve extractor
   */
  private getLocalExtractor(): LocalCurveExtractor {
    if (!this.localExtractor) {
      this.localExtractor = new LocalCurveExtractor();
    }
    return this.localExtractor;
  }

  /**
   * Get or create device-specific parser
   */
  private getDeviceParser(deviceType: CGMDeviceType): LibreGraphParser | DexcomGraphParser | null {
    switch (deviceType) {
      case 'freestyle-libre':
        if (!this.libreParser) {
          this.libreParser = new LibreGraphParser();
        }
        return this.libreParser;
      case 'dexcom':
        if (!this.dexcomParser) {
          this.dexcomParser = new DexcomGraphParser();
        }
        return this.dexcomParser;
      default:
        return null;
    }
  }

  /**
   * Get the configured ML provider and its API key
   */
  private getMLConfig(): { provider: MLProvider; apiKey: string; endpoint?: string } | null {
    if (this.settings.openaiApiKey) {
      return { provider: 'openai', apiKey: this.settings.openaiApiKey };
    }
    if (this.settings.claudeApiKey) {
      return { provider: 'claude', apiKey: this.settings.claudeApiKey };
    }
    if (this.settings.geminiApiKey) {
      return { provider: 'gemini', apiKey: this.settings.geminiApiKey };
    }
    if (this.settings.foundryEndpoint && this.settings.foundryApiKey) {
      return {
        provider: 'foundry',
        apiKey: this.settings.foundryApiKey,
        endpoint: this.settings.foundryEndpoint
      };
    }
    if (this.settings.ollamaEndpoint) {
      return {
        provider: 'ollama',
        apiKey: '',
        endpoint: this.settings.ollamaEndpoint
      };
    }
    return null;
  }

  /**
   * Convert Blob to base64 data URL
   */
  private async blobToBase64(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  /**
   * Call OpenAI Vision API
   */
  private async callOpenAI(imageBase64: string, apiKey: string): Promise<MLExtractionResponse> {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: CGM_EXTRACTION_PROMPT },
              {
                type: 'image_url',
                image_url: { url: imageBase64, detail: 'high' }
              }
            ]
          }
        ],
        max_tokens: 4096,
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`OpenAI API error: ${error}`);
    }

    const data = await response.json();
    const content = data.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No response from OpenAI');
    }

    return JSON.parse(content);
  }

  /**
   * Call Claude Vision API
   */
  private async callClaude(imageBase64: string, apiKey: string): Promise<MLExtractionResponse> {
    // Extract media type and base64 data from data URL
    const matches = imageBase64.match(/^data:([^;]+);base64,(.+)$/);
    if (!matches) {
      throw new Error('Invalid image data URL format');
    }
    const [, mediaType, base64Data] = matches;

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 4096,
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'image',
                source: {
                  type: 'base64',
                  media_type: mediaType,
                  data: base64Data
                }
              },
              { type: 'text', text: CGM_EXTRACTION_PROMPT }
            ]
          }
        ]
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Claude API error: ${error}`);
    }

    const data = await response.json();
    const content = data.content?.[0]?.text;
    if (!content) {
      throw new Error('No response from Claude');
    }

    // Extract JSON from response (Claude may include markdown code blocks)
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      throw new Error('Could not parse JSON from Claude response');
    }

    return JSON.parse(jsonMatch[0]);
  }

  /**
   * Call Gemini Vision API
   */
  private async callGemini(imageBase64: string, apiKey: string): Promise<MLExtractionResponse> {
    // Extract base64 data from data URL
    const matches = imageBase64.match(/^data:([^;]+);base64,(.+)$/);
    if (!matches) {
      throw new Error('Invalid image data URL format');
    }
    const [, mimeType, base64Data] = matches;

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: CGM_EXTRACTION_PROMPT },
                {
                  inline_data: {
                    mime_type: mimeType,
                    data: base64Data
                  }
                }
              ]
            }
          ],
          generationConfig: {
            responseMimeType: 'application/json'
          }
        })
      }
    );

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Gemini API error: ${error}`);
    }

    const data = await response.json();
    const content = data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!content) {
      throw new Error('No response from Gemini');
    }

    return JSON.parse(content);
  }

  /**
   * Call Ollama Vision API (local)
   */
  private async callOllama(
    imageBase64: string,
    endpoint: string
  ): Promise<MLExtractionResponse> {
    // Extract base64 data from data URL
    const matches = imageBase64.match(/^data:[^;]+;base64,(.+)$/);
    if (!matches) {
      throw new Error('Invalid image data URL format');
    }
    const base64Data = matches[1];

    const model = this.settings.ollamaModel || 'llava';

    const response = await fetch(`${endpoint}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        prompt: CGM_EXTRACTION_PROMPT,
        images: [base64Data],
        stream: false,
        format: 'json'
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Ollama API error: ${error}`);
    }

    const data = await response.json();
    if (!data.response) {
      throw new Error('No response from Ollama');
    }

    return JSON.parse(data.response);
  }

  /**
   * Call Azure AI Foundry API
   */
  private async callFoundry(
    imageBase64: string,
    apiKey: string,
    endpoint: string
  ): Promise<MLExtractionResponse> {
    const response = await fetch(`${endpoint}/chat/completions?api-version=2024-12-01-preview`, {
      method: 'POST',
      headers: {
        'api-key': apiKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: CGM_EXTRACTION_PROMPT },
              {
                type: 'image_url',
                image_url: { url: imageBase64, detail: 'high' }
              }
            ]
          }
        ],
        max_tokens: 4096,
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Azure Foundry API error: ${error}`);
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error('No response from Azure Foundry');
    }

    return JSON.parse(content);
  }

  /**
   * Extract using local computer vision (no API required)
   */
  private async extractWithLocalCV(
    image: Blob,
    options: CGMExtractionOptions = {}
  ): Promise<CGMExtractionResult> {
    // Try device-specific parser if device type is known
    if (options.deviceType) {
      const parser = this.getDeviceParser(options.deviceType);
      if (parser) {
        return parser.extractFromImage(image, options);
      }
    }

    // Use generic local extractor
    const extractor = this.getLocalExtractor();
    return extractor.extractFromImage(image, options);
  }

  /**
   * Extract BSL time-series from CGM graph image
   *
   * Uses ML extraction when available, with local CV as fallback.
   * Set options.useLocalExtraction = true to force local extraction.
   */
  async extractFromImage(
    image: Blob,
    options: ExtendedCGMExtractionOptions = {}
  ): Promise<CGMExtractionResult> {
    const startTime = performance.now();

    // Determine extraction method
    const preferredMethod = options.preferredMethod || 'auto';
    const useLocal = options.useLocalExtraction ||
      preferredMethod === 'local' ||
      (preferredMethod === 'auto' && !this.isConfigured());

    // Use local extraction if requested or if ML is not configured
    if (useLocal) {
      if (!LocalCurveExtractor.isAvailable()) {
        throw new Error('Local extraction requires a browser environment with Canvas support.');
      }
      return this.extractWithLocalCV(image, options);
    }

    const mlConfig = this.getMLConfig();
    if (!mlConfig) {
      // Fallback to local extraction
      if (LocalCurveExtractor.isAvailable()) {
        console.warn('No ML provider configured, falling back to local extraction.');
        return this.extractWithLocalCV(image, options);
      }
      throw new Error('No ML provider configured. Please set up an API key in Settings or use local extraction.');
    }

    const imageBase64 = await this.blobToBase64(image);

    let mlResponse: MLExtractionResponse;

    switch (mlConfig.provider) {
      case 'openai':
        mlResponse = await this.callOpenAI(imageBase64, mlConfig.apiKey);
        break;
      case 'claude':
        mlResponse = await this.callClaude(imageBase64, mlConfig.apiKey);
        break;
      case 'gemini':
        mlResponse = await this.callGemini(imageBase64, mlConfig.apiKey);
        break;
      case 'ollama':
        mlResponse = await this.callOllama(imageBase64, mlConfig.endpoint!);
        break;
      case 'foundry':
        mlResponse = await this.callFoundry(imageBase64, mlConfig.apiKey, mlConfig.endpoint!);
        break;
      default:
        throw new Error(`Unsupported ML provider: ${mlConfig.provider}`);
    }

    // Convert ML response to our format
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Use manual axis ranges if provided
    const axisRanges: AxisRanges = {
      timeStart: options.manualAxisRanges?.timeStart ||
        new Date(today.getTime() + mlResponse.axisRanges.timeStartHours * 60 * 60 * 1000),
      timeEnd: options.manualAxisRanges?.timeEnd ||
        new Date(today.getTime() + mlResponse.axisRanges.timeEndHours * 60 * 60 * 1000),
      bslMin: options.manualAxisRanges?.bslMin ?? mlResponse.axisRanges.bslMin,
      bslMax: options.manualAxisRanges?.bslMax ?? mlResponse.axisRanges.bslMax,
      unit: options.manualAxisRanges?.unit || mlResponse.axisRanges.unit
    };

    // Convert relative timestamps to absolute
    const resampleInterval = options.resampleIntervalMinutes ?? 5;
    const dataPoints: ExtractedDataPoint[] = [];

    // Sort by time and resample
    const sortedPoints = [...mlResponse.dataPoints].sort(
      (a, b) => a.minutesFromStart - b.minutesFromStart
    );

    for (const point of sortedPoints) {
      const timestamp = new Date(axisRanges.timeStart.getTime() + point.minutesFromStart * 60 * 1000);

      // Validate value is within expected range
      const isValid = point.value >= axisRanges.bslMin && point.value <= axisRanges.bslMax;

      dataPoints.push({
        timestamp,
        value: point.value,
        confidence: isValid ? 0.9 : 0.5 // Lower confidence for out-of-range values
      });
    }

    // Resample to regular intervals if needed
    const resampledPoints = this.resampleDataPoints(dataPoints, axisRanges, resampleInterval);

    const processingTimeMs = performance.now() - startTime;

    return {
      deviceType: options.deviceType || mlResponse.deviceType,
      axisRanges,
      dataPoints: resampledPoints,
      graphRegion: mlResponse.graphRegion,
      extractionMethod: 'ml',
      processingTimeMs,
      warnings: mlResponse.warnings
    };
  }

  /**
   * Resample data points to regular intervals using linear interpolation
   */
  private resampleDataPoints(
    points: ExtractedDataPoint[],
    axisRanges: AxisRanges,
    intervalMinutes: number
  ): ExtractedDataPoint[] {
    if (points.length < 2) return points;

    const result: ExtractedDataPoint[] = [];
    const startTime = axisRanges.timeStart.getTime();
    const endTime = axisRanges.timeEnd.getTime();
    const intervalMs = intervalMinutes * 60 * 1000;

    for (let t = startTime; t <= endTime; t += intervalMs) {
      // Find surrounding points
      let before: ExtractedDataPoint | null = null;
      let after: ExtractedDataPoint | null = null;

      for (const point of points) {
        const pt = point.timestamp.getTime();
        if (pt <= t && (!before || pt > before.timestamp.getTime())) {
          before = point;
        }
        if (pt >= t && (!after || pt < after.timestamp.getTime())) {
          after = point;
        }
      }

      if (before && after) {
        // Linear interpolation
        const beforeT = before.timestamp.getTime();
        const afterT = after.timestamp.getTime();

        let value: number;
        let confidence: number;

        if (beforeT === afterT) {
          value = before.value;
          confidence = before.confidence;
        } else {
          const ratio = (t - beforeT) / (afterT - beforeT);
          value = before.value + ratio * (after.value - before.value);
          confidence = Math.min(before.confidence, after.confidence) * (1 - 0.1 * ratio);
        }

        result.push({
          timestamp: new Date(t),
          value: Math.round(value * 10) / 10, // Round to 1 decimal
          confidence
        });
      } else if (before) {
        // Extrapolate from last point
        result.push({
          timestamp: new Date(t),
          value: before.value,
          confidence: before.confidence * 0.8
        });
      }
    }

    return result;
  }

  /**
   * Detect device type from image
   */
  async detectDeviceType(image: Blob): Promise<CGMDeviceType> {
    // For now, extract full data and return device type
    // Could be optimized with a lighter-weight detection prompt
    const result = await this.extractFromImage(image);
    return result.deviceType;
  }

  /**
   * Detect axis ranges from image
   */
  async detectAxisRanges(image: Blob, _region?: GraphRegion): Promise<AxisRanges> {
    // For now, extract full data and return axis ranges
    const result = await this.extractFromImage(image);
    return result.axisRanges;
  }

  /**
   * Check if device type is supported
   */
  isSupported(deviceType: CGMDeviceType): boolean {
    return ['freestyle-libre', 'dexcom', 'medtronic', 'generic'].includes(deviceType);
  }

  /**
   * Check if ML is configured
   */
  isConfigured(): boolean {
    return this.getMLConfig() !== null;
  }

  /**
   * Check if local extraction is available
   */
  isLocalExtractionAvailable(): boolean {
    return LocalCurveExtractor.isAvailable();
  }

  /**
   * Check if any extraction method is available
   */
  canExtract(): boolean {
    return this.isConfigured() || this.isLocalExtractionAvailable();
  }

  /**
   * Get the available extraction methods
   */
  getAvailableMethods(): Array<'ml' | 'local'> {
    const methods: Array<'ml' | 'local'> = [];
    if (this.isConfigured()) {
      methods.push('ml');
    }
    if (this.isLocalExtractionAvailable()) {
      methods.push('local');
    }
    return methods;
  }
}

/**
 * Factory function to create CGMImageProcessor
 */
export function createCGMImageProcessor(settings: UserSettings): CGMImageProcessor {
  return new CGMImageProcessor(settings);
}
