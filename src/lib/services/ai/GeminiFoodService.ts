/**
 * Google Gemini Pro Vision Food Recognition Service
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

interface GeminiFoodResponse {
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

interface GeminiLabelResponse {
  servingSize?: string;
  servingsPerContainer?: number;
  macros: Partial<MacroData>;
  fiber?: number;
  sugar?: number;
  sodium?: number;
  confidence: number;
}

export class GeminiFoodService implements IFoodRecognitionService {
  private apiKey: string;
  private model: string;

  constructor(apiKey: string, model: string = 'gemini-1.5-flash') {
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

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  text: `${FOOD_RECOGNITION_SYSTEM_PROMPT}\n\n${FOOD_RECOGNITION_USER_PROMPT}`
                },
                {
                  inline_data: {
                    mime_type: mimeType,
                    data: base64Image
                  }
                }
              ]
            }
          ],
          generationConfig: {
            temperature: 0.2,
            maxOutputTokens: 2000
          }
        })
      }
    );

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(
        `Gemini API error: ${response.status} - ${errorData.error?.message || response.statusText}`
      );
    }

    const data = await response.json();
    const rawResponse = data.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!rawResponse) {
      throw new Error('No response from Gemini');
    }

    const parsed = parseAIResponse<GeminiFoodResponse>(rawResponse);
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
      provider: 'gemini',
      processingTimeMs
    };
  }

  async parseNutritionLabel(image: Blob): Promise<NutritionLabelResult> {
    const base64Image = await this.blobToBase64(image);
    const mimeType = image.type || 'image/jpeg';

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${this.model}:generateContent?key=${this.apiKey}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  text: `${NUTRITION_LABEL_SYSTEM_PROMPT}\n\n${NUTRITION_LABEL_USER_PROMPT}`
                },
                {
                  inline_data: {
                    mime_type: mimeType,
                    data: base64Image
                  }
                }
              ]
            }
          ],
          generationConfig: {
            temperature: 0.1,
            maxOutputTokens: 1000
          }
        })
      }
    );

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(
        `Gemini API error: ${response.status} - ${errorData.error?.message || response.statusText}`
      );
    }

    const data = await response.json();
    const rawResponse = data.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!rawResponse) {
      throw new Error('No response from Gemini');
    }

    const parsed = parseAIResponse<GeminiLabelResponse>(rawResponse);

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
    return 'Gemini';
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
