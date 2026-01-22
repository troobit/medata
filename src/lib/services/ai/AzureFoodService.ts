/**
 * Azure OpenAI Food Recognition Service
 * Workstream A: AI-Powered Food Recognition
 *
 * Uses Azure OpenAI Service (Azure Foundry) for food recognition.
 * Compatible with GPT-4 Vision deployments.
 */

import type {
  IFoodRecognitionService,
  FoodRecognitionResult,
  NutritionLabelResult,
  RecognitionOptions,
  RecognisedFoodItem
} from '$lib/types/ai';
import type { MacroData } from '$lib/types/events';
import type { AzureConfig } from '$lib/types/settings';
import {
  FOOD_RECOGNITION_SYSTEM_PROMPT,
  FOOD_RECOGNITION_USER_PROMPT,
  NUTRITION_LABEL_SYSTEM_PROMPT,
  NUTRITION_LABEL_USER_PROMPT,
  parseAIResponse
} from './prompts/foodRecognition';

interface AzureFoodResponse {
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

interface AzureLabelResponse {
  servingSize?: string;
  servingsPerContainer?: number;
  macros: Partial<MacroData>;
  fiber?: number;
  sugar?: number;
  sodium?: number;
  confidence: number;
}

export class AzureFoodService implements IFoodRecognitionService {
  private config: AzureConfig;

  constructor(config: AzureConfig) {
    this.config = {
      ...config,
      apiVersion: config.apiVersion || '2024-02-15-preview',
      deploymentName: config.deploymentName || 'gpt-4o'
    };
  }

  private getEndpoint(): string {
    const baseUrl = this.config.endpoint?.replace(/\/$/, '');
    return `${baseUrl}/openai/deployments/${this.config.deploymentName}/chat/completions?api-version=${this.config.apiVersion}`;
  }

  async RecogniseFood(image: Blob, _options?: RecognitionOptions): Promise<FoodRecognitionResult> {
    const startTime = performance.now();

    const base64Image = await this.blobToBase64(image);
    const mimeType = image.type || 'image/jpeg';

    const response = await fetch(this.getEndpoint(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-key': this.config.apiKey!
      },
      body: JSON.stringify({
        messages: [
          {
            role: 'system',
            content: FOOD_RECOGNITION_SYSTEM_PROMPT
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: FOOD_RECOGNITION_USER_PROMPT
              },
              {
                type: 'image_url',
                image_url: {
                  url: `data:${mimeType};base64,${base64Image}`,
                  detail: 'high'
                }
              }
            ]
          }
        ],
        max_tokens: 2000,
        temperature: 0.2
      })
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(
        `Azure OpenAI API error: ${response.status} - ${errorData.error?.message || response.statusText}`
      );
    }

    const data = await response.json();
    const rawResponse = data.choices?.[0]?.message?.content;

    if (!rawResponse) {
      throw new Error('No response from Azure OpenAI');
    }

    const parsed = parseAIResponse<AzureFoodResponse>(rawResponse);
    const processingTimeMs = performance.now() - startTime;

    const items: RecognisedFoodItem[] = parsed.items.map((item) => ({
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
      provider: 'azure',
      processingTimeMs
    };
  }

  async parseNutritionLabel(image: Blob): Promise<NutritionLabelResult> {
    const base64Image = await this.blobToBase64(image);
    const mimeType = image.type || 'image/jpeg';

    const response = await fetch(this.getEndpoint(), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-key': this.config.apiKey!
      },
      body: JSON.stringify({
        messages: [
          {
            role: 'system',
            content: NUTRITION_LABEL_SYSTEM_PROMPT
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: NUTRITION_LABEL_USER_PROMPT
              },
              {
                type: 'image_url',
                image_url: {
                  url: `data:${mimeType};base64,${base64Image}`,
                  detail: 'high'
                }
              }
            ]
          }
        ],
        max_tokens: 1000,
        temperature: 0.1
      })
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(
        `Azure OpenAI API error: ${response.status} - ${errorData.error?.message || response.statusText}`
      );
    }

    const data = await response.json();
    const rawResponse = data.choices?.[0]?.message?.content;

    if (!rawResponse) {
      throw new Error('No response from Azure OpenAI');
    }

    const parsed = parseAIResponse<AzureLabelResponse>(rawResponse);

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
    return !!(this.config.apiKey && this.config.endpoint);
  }

  getProviderName(): string {
    return 'Azure OpenAI';
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
