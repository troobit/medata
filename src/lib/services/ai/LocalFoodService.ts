/**
 * Local Model Food Recognition Service
 * Workstream A: AI-Powered Food Recognition
 *
 * Supports local vision-capable models via:
 * - Ollama (native API)
 * - LM Studio (OpenAI-compatible API)
 * - OpenAI-compatible endpoints
 *
 * Requires a vision-capable model like llava, bakllava, or llava-llama3.
 */

import type {
  IFoodRecognitionService,
  FoodRecognitionResult,
  NutritionLabelResult,
  RecognitionOptions,
  RecognisedFoodItem
} from '$lib/types/ai';
import type { MacroData } from '$lib/types/events';
import type { LocalModelConfig } from '$lib/types/settings';
import {
  FOOD_RECOGNITION_SYSTEM_PROMPT,
  FOOD_RECOGNITION_USER_PROMPT,
  NUTRITION_LABEL_SYSTEM_PROMPT,
  NUTRITION_LABEL_USER_PROMPT,
  parseAIResponse
} from './prompts/foodRecognition';

interface LocalFoodResponse {
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

interface LocalLabelResponse {
  servingSize?: string;
  servingsPerContainer?: number;
  macros: Partial<MacroData>;
  fiber?: number;
  sugar?: number;
  sodium?: number;
  confidence: number;
}

export class LocalFoodService implements IFoodRecognitionService {
  private config: LocalModelConfig;

  constructor(config: LocalModelConfig) {
    this.config = {
      ...config,
      type: config.type || 'ollama',
      modelName: config.modelName || 'llava'
    };
  }

  async RecogniseFood(image: Blob, _options?: RecognitionOptions): Promise<FoodRecognitionResult> {
    const startTime = performance.now();

    const base64Image = await this.blobToBase64(image);
    const mimeType = image.type || 'image/jpeg';

    let rawResponse: string;

    if (this.config.type === 'ollama') {
      rawResponse = await this.callOllama(
        FOOD_RECOGNITION_SYSTEM_PROMPT,
        FOOD_RECOGNITION_USER_PROMPT,
        base64Image
      );
    } else {
      // LM Studio and OpenAI-compatible
      rawResponse = await this.callOpenAICompatible(
        FOOD_RECOGNITION_SYSTEM_PROMPT,
        FOOD_RECOGNITION_USER_PROMPT,
        base64Image,
        mimeType,
        2000
      );
    }

    const parsed = parseAIResponse<LocalFoodResponse>(rawResponse);
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
      provider: 'local',
      processingTimeMs
    };
  }

  async parseNutritionLabel(image: Blob): Promise<NutritionLabelResult> {
    const base64Image = await this.blobToBase64(image);
    const mimeType = image.type || 'image/jpeg';

    let rawResponse: string;

    if (this.config.type === 'ollama') {
      rawResponse = await this.callOllama(
        NUTRITION_LABEL_SYSTEM_PROMPT,
        NUTRITION_LABEL_USER_PROMPT,
        base64Image
      );
    } else {
      rawResponse = await this.callOpenAICompatible(
        NUTRITION_LABEL_SYSTEM_PROMPT,
        NUTRITION_LABEL_USER_PROMPT,
        base64Image,
        mimeType,
        1000
      );
    }

    const parsed = parseAIResponse<LocalLabelResponse>(rawResponse);

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
    return !!this.config.endpoint;
  }

  getProviderName(): string {
    const typeNames: Record<string, string> = {
      ollama: 'Ollama',
      lmstudio: 'LM Studio',
      'openai-compatible': 'Local (OpenAI-compatible)'
    };
    return typeNames[this.config.type || 'ollama'] || 'Local Model';
  }

  /**
   * Calls Ollama's native API
   */
  private async callOllama(
    systemPrompt: string,
    userPrompt: string,
    base64Image: string
  ): Promise<string> {
    const endpoint = this.config.endpoint?.replace(/\/$/, '');

    const response = await fetch(`${endpoint}/generate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: this.config.modelName,
        prompt: `${systemPrompt}\n\n${userPrompt}`,
        images: [base64Image],
        stream: false,
        options: {
          temperature: 0.2
        }
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Ollama API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    return data.response || '';
  }

  /**
   * Calls OpenAI-compatible APIs (LM Studio, etc.)
   */
  private async callOpenAICompatible(
    systemPrompt: string,
    userPrompt: string,
    base64Image: string,
    mimeType: string,
    maxTokens: number
  ): Promise<string> {
    const endpoint = this.config.endpoint?.replace(/\/$/, '');

    const response = await fetch(`${endpoint}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: this.config.modelName,
        messages: [
          {
            role: 'system',
            content: systemPrompt
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: userPrompt
              },
              {
                type: 'image_url',
                image_url: {
                  url: `data:${mimeType};base64,${base64Image}`
                }
              }
            ]
          }
        ],
        max_tokens: maxTokens,
        temperature: 0.2
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Local model API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    return data.choices?.[0]?.message?.content || '';
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
