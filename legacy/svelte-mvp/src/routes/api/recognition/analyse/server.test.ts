/**
 * Unit tests for /api/recognition/analyse endpoint.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { FoodAnalysisResult } from "$lib/services/recognition.js";
import { RecognitionError } from "$lib/services/recognition.js";

const VALID_REQUEST_BODY = {
  imageBase64: "aGVsbG8=", // small valid base64
  mimeType: "image/jpeg" as const,
};

function createMockService(overrides: {
  isReady?: boolean;
  analyseResult?: FoodAnalysisResult;
  analyseError?: Error;
}) {
  return {
    isReady: () => overrides.isReady ?? true,
    getBackendType: () => "mock",
    analyse: vi.fn().mockImplementation(async () => {
      if (overrides.analyseError) throw overrides.analyseError;
      return (
        overrides.analyseResult ?? {
          items: [
            {
              name: "Rice",
              carbs: 45,
              protein: 4,
              fat: 0.5,
              confidence: 0.9,
            },
          ],
          overallConfidence: 0.9,
        }
      );
    }),
  };
}

function createRequest(body: unknown): Request {
  return new Request("http://localhost/api/recognition/analyse", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("/api/recognition/analyse POST", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  it("returns 200 with FoodAnalysisResult on success", async () => {
    const mockResult: FoodAnalysisResult = {
      items: [
        { name: "Rice", carbs: 45, protein: 4, fat: 0.5, confidence: 0.9 },
      ],
      overallConfidence: 0.9,
      notes: "Looks good",
    };

    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () =>
        createMockService({ analyseResult: mockResult }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.items).toHaveLength(1);
    expect(body.items[0].name).toBe("Rice");
    expect(body.overallConfidence).toBe(0.9);
  });

  it("returns 503 when service is not configured (not ready)", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () => createMockService({ isReady: false }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);

    expect(response.status).toBe(503);
  });

  it("returns 504 on RecognitionError(TIMEOUT)", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () =>
        createMockService({
          analyseError: new RecognitionError("TIMEOUT"),
        }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);

    expect(response.status).toBe(504);
  });

  it("returns 422 on RecognitionError(NO_ITEMS)", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () =>
        createMockService({
          analyseError: new RecognitionError("NO_ITEMS"),
        }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);

    expect(response.status).toBe(422);
  });

  it("returns 413 when imageBase64 exceeds 14,000,000 characters", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () => createMockService({}),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const oversizedBody = {
      imageBase64: "A".repeat(14_000_001),
      mimeType: "image/jpeg",
    };
    const response = await POST({
      request: createRequest(oversizedBody),
    } as any);

    expect(response.status).toBe(413);
  });

  it("returns 429 when upstream returns 429 (RecognitionError(BACKEND_ERROR, 429))", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () =>
        createMockService({
          analyseError: new RecognitionError("BACKEND_ERROR", 429),
        }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);

    expect(response.status).toBe(429);
  });

  it("returns 503 on RecognitionError(BACKEND_ERROR) without 429", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () =>
        createMockService({
          analyseError: new RecognitionError("BACKEND_ERROR", 500),
        }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);

    expect(response.status).toBe(503);
  });

  it("returns 502 on RecognitionError(INVALID_RESPONSE)", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () =>
        createMockService({
          analyseError: new RecognitionError("INVALID_RESPONSE"),
        }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);

    expect(response.status).toBe(502);
  });

  it("uses Irish English spelling in error messages (Req 11.4)", async () => {
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () =>
        createMockService({
          analyseError: new RecognitionError("NO_ITEMS"),
        }),
      RecognitionError,
    }));

    const { POST } = await import("./+server.js");
    const response = await POST({
      request: createRequest(VALID_REQUEST_BODY),
    } as any);
    const body = await response.json();

    // Should use "recognise" not "recognize"
    expect(body.error).toBeDefined();
    expect(body.error).not.toMatch(/recognize/i);
    // Check for Irish English spellings where applicable
    if (body.error.toLowerCase().includes("recogni")) {
      expect(body.error).toMatch(/recognis/i);
    }
  });
});
