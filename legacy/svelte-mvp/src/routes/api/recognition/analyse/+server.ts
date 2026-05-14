import { json } from "@sveltejs/kit";
import {
  createRecognitionService,
  RecognitionError,
} from "$lib/services/recognition.js";

const MAX_BASE64_CHARS = 14_000_000; // ~10MB binary

export async function POST({ request }: { request: Request }) {
  const body = await request.json();
  const { imageBase64, mimeType } = body as {
    imageBase64: string;
    mimeType: string;
  };

  // Validate image size
  if (imageBase64.length > MAX_BASE64_CHARS) {
    return json(
      { error: "Image too large — maximum size is 10MB." },
      { status: 413 },
    );
  }

  // Create service and check readiness
  const service = createRecognitionService();
  if (!service.isReady()) {
    return json(
      {
        error:
          "Recognition service is not configured. Set RECOGNITION_BASE_URL and RECOGNITION_MODEL in .env.",
      },
      { status: 503 },
    );
  }

  try {
    // Convert base64 to Blob
    const binaryString = atob(imageBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: mimeType });

    const result = await service.analyse(blob);
    return json(result);
  } catch (err) {
    if (err instanceof RecognitionError) {
      switch (err.code) {
        case "TIMEOUT":
          return json(
            { error: "Recognition timed out. Please try again." },
            { status: 504 },
          );
        case "NO_ITEMS":
          return json(
            { error: "Couldn't recognise any food items in this image." },
            { status: 422 },
          );
        case "INVALID_RESPONSE":
          return json(
            {
              error:
                "Recognition service returned an invalid response. Please try again.",
            },
            { status: 502 },
          );
        case "BACKEND_ERROR":
          if (err.httpStatus === 429) {
            return json(
              {
                error:
                  "Too many requests — please wait a moment and try again.",
              },
              { status: 429 },
            );
          }
          return json(
            { error: "Recognition service is temporarily unavailable." },
            { status: 503 },
          );
        case "NOT_CONFIGURED":
          return json(
            { error: "Recognition service is not configured." },
            { status: 503 },
          );
      }
    }

    return json(
      { error: "An unexpected error occurred during recognition." },
      { status: 500 },
    );
  }
}
