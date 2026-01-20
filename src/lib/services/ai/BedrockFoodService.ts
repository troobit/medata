/**
 * Amazon Bedrock Food Recognition Service
 * Workstream A: AI-Powered Food Recognition
 *
 * Uses Amazon Bedrock for food recognition with Claude models.
 * Implements AWS Signature V4 signing for browser compatibility.
 */

import type {
  IFoodRecognitionService,
  FoodRecognitionResult,
  NutritionLabelResult,
  RecognitionOptions,
  RecognizedFoodItem
} from '$lib/types/ai';
import type { MacroData } from '$lib/types/events';
import type { BedrockConfig } from '$lib/types/settings';
import {
  FOOD_RECOGNITION_SYSTEM_PROMPT,
  FOOD_RECOGNITION_USER_PROMPT,
  NUTRITION_LABEL_SYSTEM_PROMPT,
  NUTRITION_LABEL_USER_PROMPT,
  parseAIResponse
} from './prompts/foodRecognition';

interface BedrockFoodResponse {
  items: Array<{
    name: string;
    quantity?: number;
    unit?: string;
    macros?: Partial<MacroData>;
    confidence: number;
  }>;
  totalMacros: MacroData;
  confidence: number;
}

interface BedrockLabelResponse {
  servingSize?: string;
  servingsPerContainer?: number;
  macros: Partial<MacroData>;
  fiber?: number;
  sugar?: number;
  sodium?: number;
  confidence: number;
}

export class BedrockFoodService implements IFoodRecognitionService {
  private config: BedrockConfig;

  constructor(config: BedrockConfig) {
    this.config = {
      ...config,
      region: config.region || 'us-east-1',
      modelId: config.modelId || 'anthropic.claude-3-sonnet-20240229-v1:0'
    };
  }

  async recognizeFood(image: Blob, _options?: RecognitionOptions): Promise<FoodRecognitionResult> {
    const startTime = performance.now();

    const base64Image = await this.blobToBase64(image);
    const mimeType = (image.type || 'image/jpeg') as 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp';

    // Bedrock uses Claude's message format for Anthropic models
    const requestBody = {
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 2000,
      temperature: 0.2,
      system: FOOD_RECOGNITION_SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: FOOD_RECOGNITION_USER_PROMPT
            },
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: mimeType,
                data: base64Image
              }
            }
          ]
        }
      ]
    };

    const response = await this.invokeModel(requestBody);
    const processingTimeMs = performance.now() - startTime;

    const rawResponse = response.content?.[0]?.text;
    if (!rawResponse) {
      throw new Error('No response from Bedrock');
    }

    const parsed = parseAIResponse<BedrockFoodResponse>(rawResponse);

    const items: RecognizedFoodItem[] = parsed.items.map((item) => ({
      name: item.name,
      quantity: item.quantity,
      unit: item.unit,
      macros: item.macros,
      confidence: item.confidence
    }));

    return {
      items,
      totalMacros: parsed.totalMacros,
      confidence: parsed.confidence,
      rawResponse,
      provider: 'bedrock',
      processingTimeMs
    };
  }

  async parseNutritionLabel(image: Blob): Promise<NutritionLabelResult> {
    const base64Image = await this.blobToBase64(image);
    const mimeType = (image.type || 'image/jpeg') as 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp';

    const requestBody = {
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 1000,
      temperature: 0.1,
      system: NUTRITION_LABEL_SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: NUTRITION_LABEL_USER_PROMPT
            },
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: mimeType,
                data: base64Image
              }
            }
          ]
        }
      ]
    };

    const response = await this.invokeModel(requestBody);

    const rawResponse = response.content?.[0]?.text;
    if (!rawResponse) {
      throw new Error('No response from Bedrock');
    }

    const parsed = parseAIResponse<BedrockLabelResponse>(rawResponse);

    return {
      servingSize: parsed.servingSize,
      servingsPerContainer: parsed.servingsPerContainer,
      macros: parsed.macros,
      fiber: parsed.fiber,
      sugar: parsed.sugar,
      sodium: parsed.sodium,
      confidence: parsed.confidence
    };
  }

  isConfigured(): boolean {
    return !!(
      this.config.accessKeyId &&
      this.config.secretAccessKey &&
      this.config.region
    );
  }

  getProviderName(): string {
    return 'Amazon Bedrock';
  }

  private async invokeModel(body: object): Promise<{ content: Array<{ text: string }> }> {
    const region = this.config.region!;
    const modelId = this.config.modelId!;
    const endpoint = `https://bedrock-runtime.${region}.amazonaws.com/model/${modelId}/invoke`;

    const payload = JSON.stringify(body);
    const now = new Date();

    // Sign the request using AWS Signature V4
    const headers = await this.signRequest('POST', endpoint, payload, now);

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        ...headers,
        'Content-Type': 'application/json'
      },
      body: payload
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Bedrock API error: ${response.status} - ${errorText}`);
    }

    return response.json();
  }

  /**
   * Signs a request using AWS Signature Version 4
   * Browser-compatible implementation without external dependencies
   */
  private async signRequest(
    method: string,
    url: string,
    payload: string,
    date: Date
  ): Promise<Record<string, string>> {
    const urlObj = new URL(url);
    const host = urlObj.host;
    const path = urlObj.pathname;
    const region = this.config.region!;
    const service = 'bedrock';

    // Format dates
    const amzDate = date.toISOString().replace(/[:-]|\.\d{3}/g, '');
    const dateStamp = amzDate.slice(0, 8);

    // Create canonical request
    const payloadHash = await this.sha256Hex(payload);
    const canonicalHeaders = `host:${host}\nx-amz-date:${amzDate}\n`;
    const signedHeaders = 'host;x-amz-date';

    const canonicalRequest = [
      method,
      path,
      '', // query string
      canonicalHeaders,
      signedHeaders,
      payloadHash
    ].join('\n');

    // Create string to sign
    const algorithm = 'AWS4-HMAC-SHA256';
    const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;
    const canonicalRequestHash = await this.sha256Hex(canonicalRequest);

    const stringToSign = [algorithm, amzDate, credentialScope, canonicalRequestHash].join('\n');

    // Calculate signature
    const signingKey = await this.getSignatureKey(dateStamp, region, service);
    const signature = await this.hmacHex(signingKey, stringToSign);

    // Create authorization header
    const accessKey = this.config.accessKeyId!;
    const authorization = `${algorithm} Credential=${accessKey}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

    return {
      Authorization: authorization,
      'X-Amz-Date': amzDate,
      'X-Amz-Content-Sha256': payloadHash
    };
  }

  private async getSignatureKey(
    dateStamp: string,
    region: string,
    service: string
  ): Promise<ArrayBuffer> {
    const secretKey = this.config.secretAccessKey!;
    const kDate = await this.hmac(`AWS4${secretKey}`, dateStamp);
    const kRegion = await this.hmac(kDate, region);
    const kService = await this.hmac(kRegion, service);
    return this.hmac(kService, 'aws4_request');
  }

  private async sha256Hex(message: string): Promise<string> {
    const encoder = new TextEncoder();
    const data = encoder.encode(message);
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    return this.bufferToHex(hashBuffer);
  }

  private async hmac(key: string | ArrayBuffer, message: string): Promise<ArrayBuffer> {
    const encoder = new TextEncoder();
    const keyData = typeof key === 'string' ? encoder.encode(key) : key;

    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyData,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );

    return crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(message));
  }

  private async hmacHex(key: ArrayBuffer, message: string): Promise<string> {
    const result = await this.hmac(key, message);
    return this.bufferToHex(result);
  }

  private bufferToHex(buffer: ArrayBuffer): string {
    return Array.from(new Uint8Array(buffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  private async blobToBase64(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => {
        const result = reader.result as string;
        const base64 = result.split(',')[1];
        resolve(base64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }
}
