import type { OpenAIVisionResponse, VisionAnalysisOptions } from '$lib/types/vision';

const OPENAI_API_URL = 'https://api.openai.com/v1/chat/completions';
const DEFAULT_MODEL = 'gpt-4o';
const DEFAULT_MAX_TOKENS = 4096;

export class VisionServiceError extends Error {
  constructor(
    message: string,
    public readonly code?: string,
    public readonly statusCode?: number
  ) {
    super(message);
    this.name = 'VisionServiceError';
  }
}

/**
 * Service for interacting with OpenAI Vision API
 */
export class VisionService {
  private apiKey: string;

  constructor(apiKey?: string) {
    this.apiKey = apiKey || import.meta.env.VITE_OPENAI_API_KEY || '';
  }

  /**
   * Check if the service is configured with an API key
   */
  isConfigured(): boolean {
    return this.apiKey.length > 0;
  }

  /**
   * Analyse an image using GPT-4o Vision
   * @param imageBase64 Base64-encoded image data (without data URL prefix)
   * @param prompt The prompt to send with the image
   * @param options Optional configuration
   * @returns The text response from the model
   */
  async analyzeImage(
    imageBase64: string,
    prompt: string,
    options: VisionAnalysisOptions = {}
  ): Promise<string> {
    if (!this.isConfigured()) {
      throw new VisionServiceError(
        'OpenAI API key not configured. Set VITE_OPENAI_API_KEY environment variable.',
        'API_KEY_MISSING'
      );
    }

    const model = options.model || DEFAULT_MODEL;
    const maxTokens = options.maxTokens || DEFAULT_MAX_TOKENS;

    // Determine image type from base64 header or default to jpeg
    const mimeType = this.detectMimeType(imageBase64);

    const requestBody = {
      model,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            {
              type: 'image_url',
              image_url: {
                url: `data:${mimeType};base64,${imageBase64}`
              }
            }
          ]
        }
      ],
      max_tokens: maxTokens
    };

    try {
      const response = await fetch(OPENAI_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`
        },
        body: JSON.stringify(requestBody)
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        const errorMessage = errorData?.error?.message || `HTTP ${response.status}`;

        if (response.status === 401) {
          throw new VisionServiceError('Invalid API key', 'INVALID_API_KEY', 401);
        }
        if (response.status === 429) {
          throw new VisionServiceError(
            'Rate limit exceeded. Please try again later.',
            'RATE_LIMIT',
            429
          );
        }
        if (response.status >= 500) {
          throw new VisionServiceError(
            'OpenAI service unavailable. Please try again later.',
            'SERVICE_UNAVAILABLE',
            response.status
          );
        }

        throw new VisionServiceError(errorMessage, 'API_ERROR', response.status);
      }

      const data: OpenAIVisionResponse = await response.json();

      if (!data.choices?.[0]?.message?.content) {
        throw new VisionServiceError('No response content from API', 'EMPTY_RESPONSE');
      }

      return data.choices[0].message.content;
    } catch (error) {
      if (error instanceof VisionServiceError) {
        throw error;
      }
      if (error instanceof TypeError && error.message.includes('fetch')) {
        throw new VisionServiceError(
          'Network error. Please check your internet connection.',
          'NETWORK_ERROR'
        );
      }
      throw new VisionServiceError(
        error instanceof Error ? error.message : 'Unknown error occurred',
        'UNKNOWN_ERROR'
      );
    }
  }

  /**
   * Detect MIME type from base64 data
   */
  private detectMimeType(base64: string): string {
    // Check for common image signatures in base64
    if (base64.startsWith('/9j/')) return 'image/jpeg';
    if (base64.startsWith('iVBORw0KGgo')) return 'image/png';
    if (base64.startsWith('R0lGOD')) return 'image/gif';
    if (base64.startsWith('UklGR')) return 'image/webp';
    // Default to JPEG
    return 'image/jpeg';
  }
}

// Singleton instance
let visionService: VisionService | null = null;

export function getVisionService(): VisionService {
  if (!visionService) {
    visionService = new VisionService();
  }
  return visionService;
}
