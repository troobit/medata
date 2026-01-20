/**
 * OpenAI Vision (GPT-4V) Food Recognition Service
 * Workstream A: AI-Powered Food Recognition
 */

import type {
  IFoodRecognitionService,
  FoodRecognitionResult,
  NutritionLabelResult,
  RecognitionOptions,
  RecognizedFoodItem
} from '$lib/types/ai';
import type { MacroData } from '$lib/types/events';
import {
  FOOD_RECOGNITION_SYSTEM_PROMPT,
  FOOD_RECOGNITION_USER_PROMPT,
  NUTRITION_LABEL_SYSTEM_PROMPT,
  NUTRITION_LABEL_USER_PROMPT,
  parseAIResponse
} from './prompts/foodRecognition';

interface OpenAIFoodResponse {
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

interface OpenAILabelResponse {
  servingSize?: string;
  servingsPerContainer?: number;
  macros: Partial<MacroData>;
  fiber?: number;
  sugar?: number;
  sodium?: number;
  confidence: number;
}

export class OpenAIFoodService implements IFoodRecognitionService {
  private apiKey: string;
  private model: string;

  constructor(apiKey: string, model: string = 'gpt-4o') {
    this.apiKey = apiKey;
    this.model = model;
  }

  async recognizeFood(
    image: Blob,
    options?: RecognitionOptions
  ): Promise<FoodRecognitionResult> {
    const startTime = performance.now();

    const base64Image = await this.blobToBase64(image);
    const mimeType = image.type || 'image/jpeg';

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.apiKey}`
      },
      body: JSON.stringify({
        model: this.model,
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
        `OpenAI API error: ${response.status} - ${errorData.error?.message || response.statusText}`
      );
    }

    const data = await response.json();
    const rawResponse = data.choices?.[0]?.message?.content;

    if (!rawResponse) {
      throw new Error('No response from OpenAI');
    }

    const parsed = parseAIResponse<OpenAIFoodResponse>(rawResponse);
    const processingTimeMs = performance.now() - startTime;

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
      provider: 'openai',
      processingTimeMs
    };
  }

  async parseNutritionLabel(image: Blob): Promise<NutritionLabelResult> {
    const base64Image = await this.blobToBase64(image);
    const mimeType = image.type || 'image/jpeg';

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.apiKey}`
      },
      body: JSON.stringify({
        model: this.model,
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
        `OpenAI API error: ${response.status} - ${errorData.error?.message || response.statusText}`
      );
    }

    const data = await response.json();
    const rawResponse = data.choices?.[0]?.message?.content;

    if (!rawResponse) {
      throw new Error('No response from OpenAI');
    }

    const parsed = parseAIResponse<OpenAILabelResponse>(rawResponse);

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
    return !!this.apiKey;
  }

  getProviderName(): string {
    return 'OpenAI';
  }

  private async blobToBase64(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => {
        const result = reader.result as string;
        // Remove the data URL prefix to get just the base64
        const base64 = result.split(',')[1];
        resolve(base64);
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }
}
