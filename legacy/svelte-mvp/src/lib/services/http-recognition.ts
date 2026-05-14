/**
 * HTTP-based recognition service implementation.
 * Makes OpenAI-compatible /v1/chat/completions requests to any configured backend.
 * No vendor-specific logic — works with Ollama, DeepSeek, LM Studio, or any compatible endpoint.
 */
import type {
  IRecognitionService,
  FoodAnalysisResult,
  AnalysedFoodItem,
} from "./recognition.js";
import { RecognitionError } from "./recognition.js";

const RECOGNITION_PROMPT = `You are a nutrition analysis assistant helping a person with Type 1 diabetes track their food intake. Your task is to identify foods in the image and estimate macronutrients as accurately as possible.

CONTEXT:
- The user needs accurate carbohydrate estimates for insulin dosing
- Precision matters more than conservative estimates
- The user is medically informed and does not need health disclaimers

ANALYSIS INSTRUCTIONS:

1. IDENTIFY each distinct food item visible in the image
2. ESTIMATE the portion size using visual cues:
   - Standard plate sizes (dinner plate ~26cm, side plate ~15cm)
   - Common reference objects if visible (cutlery, hands, cups)
   - Typical serving sizes for the identified food
3. CALCULATE macronutrients for each item based on portion estimate
4. ASSIGN a confidence score (0-1) reflecting:
   - Clarity of food identification (0.9+ if clearly visible)
   - Portion estimation certainty (reduce if size unclear)
   - Food preparation uncertainty (reduce if cooking method unclear)

OUTPUT FORMAT:
Return ONLY valid JSON matching this structure:
{
  "items": [
    {
      "name": "Food name",
      "carbs": 25,
      "protein": 8,
      "fat": 12,
      "confidence": 0.85
    }
  ],
  "overallConfidence": 0.85,
  "notes": "Optional observations"
}

All macro values in grams. Confidence between 0 and 1.`;

/**
 * Convert a Blob to base64 string.
 */
async function blobToBase64(blob: Blob): Promise<string> {
  const buffer = await blob.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary);
}

/**
 * Build the messages array for an OpenAI-compat chat completions request.
 */
function buildMessages(
  imageBase64: string,
  mimeType: string,
): Array<{
  role: string;
  content: Array<{ type: string; [key: string]: unknown }>;
}> {
  return [
    {
      role: "user",
      content: [
        {
          type: "image_url",
          image_url: { url: `data:${mimeType};base64,${imageBase64}` },
        },
        {
          type: "text",
          text: RECOGNITION_PROMPT,
        },
      ],
    },
  ];
}

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * Parse and validate a FoodAnalysisResult from an OpenAI-compat response envelope.
 * Handles backends that ignore response_format and return freeform text or markdown-fenced JSON.
 *
 * @throws RecognitionError('INVALID_RESPONSE') on any schema violation
 * @throws RecognitionError('NO_ITEMS') if items array is empty
 */
export function parseAnalysisResult(data: any): FoodAnalysisResult {
  // Extract content from OpenAI-compat envelope
  let content: any;
  try {
    content = data.choices[0].message.content;
  } catch {
    throw new RecognitionError("INVALID_RESPONSE");
  }

  // If content is already an object (pre-parsed), use it directly
  let parsed: any;
  if (typeof content === "object" && content !== null) {
    parsed = content;
  } else if (typeof content === "string") {
    // Strip markdown fences if present
    let jsonString = content;
    const fenceMatch = jsonString.match(
      /^```(?:json)?\s*\n?([\s\S]*?)\n?```\s*$/,
    );
    if (fenceMatch?.[1]) {
      jsonString = fenceMatch[1].trim();
    }

    try {
      parsed = JSON.parse(jsonString);
    } catch {
      throw new RecognitionError("INVALID_RESPONSE");
    }
  } else {
    throw new RecognitionError("INVALID_RESPONSE");
  }

  // Validate top-level fields
  if (!Array.isArray(parsed.items)) {
    throw new RecognitionError("INVALID_RESPONSE");
  }
  if (
    typeof parsed.overallConfidence !== "number" ||
    parsed.overallConfidence < 0 ||
    parsed.overallConfidence > 1
  ) {
    throw new RecognitionError("INVALID_RESPONSE");
  }

  // Check for empty items
  if (parsed.items.length === 0) {
    throw new RecognitionError("NO_ITEMS");
  }

  // Validate each item
  const items: AnalysedFoodItem[] = [];
  for (const item of parsed.items) {
    if (typeof item.name !== "string")
      throw new RecognitionError("INVALID_RESPONSE");
    if (typeof item.carbs !== "number" || item.carbs < 0)
      throw new RecognitionError("INVALID_RESPONSE");
    if (typeof item.protein !== "number" || item.protein < 0)
      throw new RecognitionError("INVALID_RESPONSE");
    if (typeof item.fat !== "number" || item.fat < 0)
      throw new RecognitionError("INVALID_RESPONSE");
    if (
      typeof item.confidence !== "number" ||
      item.confidence < 0 ||
      item.confidence > 1
    ) {
      throw new RecognitionError("INVALID_RESPONSE");
    }

    items.push({
      name: item.name,
      carbs: item.carbs,
      protein: item.protein,
      fat: item.fat,
      confidence: item.confidence,
    });
  }

  return {
    items,
    overallConfidence: parsed.overallConfidence,
    ...(parsed.notes !== undefined ? { notes: String(parsed.notes) } : {}),
  };
}

/* eslint-enable @typescript-eslint/no-explicit-any */

/**
 * HTTP-based recognition service.
 * Sends requests to any OpenAI-compatible /v1/chat/completions endpoint.
 */
export class HttpRecognitionService implements IRecognitionService {
  private readonly baseUrl: string;
  private readonly model: string;
  private readonly apiKey: string | undefined;
  private readonly timeoutMs: number;

  constructor() {
    this.baseUrl = process.env["RECOGNITION_BASE_URL"] ?? "";
    this.model = process.env["RECOGNITION_MODEL"] ?? "";
    this.apiKey = process.env["RECOGNITION_API_KEY"] || undefined;
    this.timeoutMs = parseInt(
      process.env["RECOGNITION_TIMEOUT_MS"] ?? "10000",
      10,
    );
  }

  isReady(): boolean {
    return this.baseUrl.length > 0 && this.model.length > 0;
  }

  getBackendType(): string {
    return "http";
  }

  async analyse(image: Blob): Promise<FoodAnalysisResult> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    const imageBase64 = await blobToBase64(image);
    const messages = buildMessages(imageBase64, image.type);

    try {
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (this.apiKey) {
        headers["Authorization"] = `Bearer ${this.apiKey}`;
      }

      const response = await fetch(`${this.baseUrl}/v1/chat/completions`, {
        method: "POST",
        signal: controller.signal,
        headers,
        body: JSON.stringify({
          model: this.model,
          messages,
          response_format: { type: "json_object" },
        }),
      });

      if (!response.ok) {
        throw new RecognitionError("BACKEND_ERROR", response.status);
      }

      const data = await response.json();
      return parseAnalysisResult(data);
    } catch (err) {
      if (err instanceof RecognitionError) throw err;
      if ((err as Error).name === "AbortError") {
        throw new RecognitionError("TIMEOUT");
      }
      throw err;
    } finally {
      clearTimeout(timeout);
    }
  }
}
