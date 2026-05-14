/**
 * Unit tests for parseAnalysisResult and HttpRecognitionService.
 * Test-first: these tests are written before the implementation.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

/**
 * Helper: assert an error is a RecognitionError with expected code.
 * Uses name + code checks instead of instanceof to avoid cross-module identity issues
 * caused by vi.resetModules().
 */
function expectRecognitionError(
  err: unknown,
  code: string,
  httpStatus?: number,
) {
  expect(err).toBeDefined();
  expect((err as Error).name).toBe("RecognitionError");
  expect((err as { code: string }).code).toBe(code);
  if (httpStatus !== undefined) {
    expect((err as { httpStatus: number }).httpStatus).toBe(httpStatus);
  }
}

/**
 * Create a Blob-like object that works in jsdom (which may lack arrayBuffer()).
 */
function createTestBlob(content: string, type: string): Blob {
  const blob = new Blob([content], { type });
  // Polyfill arrayBuffer if missing in jsdom
  if (typeof blob.arrayBuffer !== "function") {
    (blob as { arrayBuffer: () => Promise<ArrayBuffer> }).arrayBuffer = () =>
      Promise.resolve(new TextEncoder().encode(content).buffer as ArrayBuffer);
  }
  return blob;
}

// ─── parseAnalysisResult tests ──────────────────────────────────────────────

describe("parseAnalysisResult", () => {
  let parseAnalysisResult: typeof import("./http-recognition.js").parseAnalysisResult;

  beforeEach(async () => {
    vi.resetModules();
    vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
    vi.stubEnv("RECOGNITION_MODEL", "llava");
    const mod = await import("./http-recognition.js");
    parseAnalysisResult = mod.parseAnalysisResult;
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("returns valid FoodAnalysisResult for well-formed OpenAI-compat response", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({
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
              notes: "Looks like white rice.",
            }),
          },
        },
      ],
    };

    const result = parseAnalysisResult(response);
    expect(result.items).toHaveLength(1);
    expect(result.items[0]!.name).toBe("Rice");
    expect(result.items[0]!.carbs).toBe(45);
    expect(result.items[0]!.protein).toBe(4);
    expect(result.items[0]!.fat).toBe(0.5);
    expect(result.items[0]!.confidence).toBe(0.9);
    expect(result.overallConfidence).toBe(0.9);
    expect(result.notes).toBe("Looks like white rice.");
  });

  it("extracts JSON from markdown-fenced response (strips ```json wrapper)", () => {
    const response = {
      choices: [
        {
          message: {
            content:
              '```json\n{"items":[{"name":"Pasta","carbs":40,"protein":7,"fat":1,"confidence":0.85}],"overallConfidence":0.85}\n```',
          },
        },
      ],
    };

    const result = parseAnalysisResult(response);
    expect(result.items).toHaveLength(1);
    expect(result.items[0]!.name).toBe("Pasta");
  });

  it("strips bare ``` fence without language tag", () => {
    const response = {
      choices: [
        {
          message: {
            content:
              '```\n{"items":[{"name":"Salad","carbs":5,"protein":2,"fat":3,"confidence":0.8}],"overallConfidence":0.8}\n```',
          },
        },
      ],
    };

    const result = parseAnalysisResult(response);
    expect(result.items[0]!.name).toBe("Salad");
  });

  it("throws RecognitionError(INVALID_RESPONSE) when content is not parseable JSON", () => {
    const response = {
      choices: [{ message: { content: "This is not JSON at all" } }],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });

  it("throws RecognitionError(INVALID_RESPONSE) when required fields missing", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({ somethingElse: true }),
          },
        },
      ],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });

  it("throws RecognitionError(INVALID_RESPONSE) when items is not an array", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({
              items: "not an array",
              overallConfidence: 0.8,
            }),
          },
        },
      ],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });

  it("throws RecognitionError(INVALID_RESPONSE) when item has wrong types", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({
              items: [
                {
                  name: 123,
                  carbs: "not a number",
                  protein: 0,
                  fat: 0,
                  confidence: 0.5,
                },
              ],
              overallConfidence: 0.5,
            }),
          },
        },
      ],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });

  it("throws RecognitionError(INVALID_RESPONSE) when item has negative macro values", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({
              items: [
                {
                  name: "Food",
                  carbs: -5,
                  protein: 0,
                  fat: 0,
                  confidence: 0.5,
                },
              ],
              overallConfidence: 0.5,
            }),
          },
        },
      ],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });

  it("throws RecognitionError(INVALID_RESPONSE) when confidence is out of range", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({
              items: [
                {
                  name: "Food",
                  carbs: 10,
                  protein: 5,
                  fat: 2,
                  confidence: 1.5,
                },
              ],
              overallConfidence: 0.8,
            }),
          },
        },
      ],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });

  it("throws RecognitionError(NO_ITEMS) when items array is empty", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({
              items: [],
              overallConfidence: 0,
            }),
          },
        },
      ],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "NO_ITEMS");
    }
  });

  it("handles choices[0].message.content as object (pre-parsed JSON)", () => {
    const response = {
      choices: [
        {
          message: {
            content: {
              items: [
                {
                  name: "Soup",
                  carbs: 15,
                  protein: 8,
                  fat: 4,
                  confidence: 0.75,
                },
              ],
              overallConfidence: 0.75,
            },
          },
        },
      ],
    };

    const result = parseAnalysisResult(response);
    expect(result.items).toHaveLength(1);
    expect(result.items[0]!.name).toBe("Soup");
  });

  it("throws RecognitionError(INVALID_RESPONSE) when choices array is missing", () => {
    try {
      parseAnalysisResult({});
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });

  it("throws RecognitionError(INVALID_RESPONSE) when overallConfidence is not a number", () => {
    const response = {
      choices: [
        {
          message: {
            content: JSON.stringify({
              items: [
                {
                  name: "Food",
                  carbs: 10,
                  protein: 5,
                  fat: 2,
                  confidence: 0.8,
                },
              ],
              overallConfidence: "high",
            }),
          },
        },
      ],
    };

    try {
      parseAnalysisResult(response);
      expect.unreachable("should have thrown");
    } catch (err) {
      expectRecognitionError(err, "INVALID_RESPONSE");
    }
  });
});

// ─── HttpRecognitionService tests ───────────────────────────────────────────

describe("HttpRecognitionService", () => {
  let HttpRecognitionService: typeof import("./http-recognition.js").HttpRecognitionService;

  beforeEach(async () => {
    vi.resetModules();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  describe("isReady()", () => {
    it("returns false when RECOGNITION_BASE_URL is unset", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "");
      vi.stubEnv("RECOGNITION_MODEL", "llava");
      const mod = await import("./http-recognition.js");
      HttpRecognitionService = mod.HttpRecognitionService;

      const service = new HttpRecognitionService();
      expect(service.isReady()).toBe(false);
    });

    it("returns false when RECOGNITION_MODEL is unset", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "");
      const mod = await import("./http-recognition.js");
      HttpRecognitionService = mod.HttpRecognitionService;

      const service = new HttpRecognitionService();
      expect(service.isReady()).toBe(false);
    });

    it("returns true when both RECOGNITION_BASE_URL and RECOGNITION_MODEL are set", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "llava");
      const mod = await import("./http-recognition.js");
      HttpRecognitionService = mod.HttpRecognitionService;

      const service = new HttpRecognitionService();
      expect(service.isReady()).toBe(true);
    });
  });

  describe("getBackendType()", () => {
    it("returns 'http'", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "llava");
      const mod = await import("./http-recognition.js");
      HttpRecognitionService = mod.HttpRecognitionService;

      const service = new HttpRecognitionService();
      expect(service.getBackendType()).toBe("http");
    });
  });

  describe("analyse()", () => {
    const validResponse = {
      choices: [
        {
          message: {
            content: JSON.stringify({
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
            }),
          },
        },
      ],
    };

    it("sends correct OpenAI-compat request body shape", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "test-model");
      vi.stubEnv("RECOGNITION_API_KEY", "test-key");

      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve(validResponse),
      });
      vi.stubGlobal("fetch", fetchMock);

      const mod = await import("./http-recognition.js");
      const service = new mod.HttpRecognitionService();
      const blob = createTestBlob("fake image", "image/jpeg");
      await service.analyse(blob);

      expect(fetchMock).toHaveBeenCalledOnce();
      const [url, options] = fetchMock.mock.calls[0]!;
      expect(url).toBe("http://localhost:11434/v1/chat/completions");
      expect(options.method).toBe("POST");

      const body = JSON.parse(options.body);
      expect(body.model).toBe("test-model");
      expect(body.messages).toHaveLength(1);
      expect(body.messages[0].role).toBe("user");
      expect(body.response_format).toEqual({ type: "json_object" });

      // Content should have image_url and text parts
      const content = body.messages[0].content;
      expect(content).toHaveLength(2);
      expect(content[0].type).toBe("image_url");
      expect(content[0].image_url.url).toMatch(/^data:image\/jpeg;base64,/);
      expect(content[1].type).toBe("text");
    });

    it("includes Authorization: Bearer header when RECOGNITION_API_KEY is set", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "llava");
      vi.stubEnv("RECOGNITION_API_KEY", "sk-test-key-123");

      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve(validResponse),
      });
      vi.stubGlobal("fetch", fetchMock);

      const mod = await import("./http-recognition.js");
      const service = new mod.HttpRecognitionService();
      const blob = createTestBlob("fake image", "image/jpeg");
      await service.analyse(blob);

      const [, options] = fetchMock.mock.calls[0]!;
      expect(options.headers["Authorization"]).toBe("Bearer sk-test-key-123");
    });

    it("omits Authorization header when RECOGNITION_API_KEY is not set", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "llava");
      // Don't set RECOGNITION_API_KEY

      const fetchMock = vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.resolve(validResponse),
      });
      vi.stubGlobal("fetch", fetchMock);

      const mod = await import("./http-recognition.js");
      const service = new mod.HttpRecognitionService();
      const blob = createTestBlob("fake image", "image/jpeg");
      await service.analyse(blob);

      const [, options] = fetchMock.mock.calls[0]!;
      expect(options.headers).not.toHaveProperty("Authorization");
    });

    it("throws RecognitionError(BACKEND_ERROR, httpStatus) for non-200 responses", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "llava");

      const fetchMock = vi.fn().mockResolvedValue({
        ok: false,
        status: 503,
      });
      vi.stubGlobal("fetch", fetchMock);

      const mod = await import("./http-recognition.js");
      const service = new mod.HttpRecognitionService();
      const blob = createTestBlob("fake image", "image/jpeg");

      try {
        await service.analyse(blob);
        expect.unreachable("should have thrown");
      } catch (err) {
        expectRecognitionError(err, "BACKEND_ERROR", 503);
      }
    });

    it("throws RecognitionError(TIMEOUT) when fetch is aborted after timeout", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "llava");
      vi.stubEnv("RECOGNITION_TIMEOUT_MS", "100");

      const fetchMock = vi
        .fn()
        .mockImplementation(
          (_url: string, options: { signal: AbortSignal }) => {
            return new Promise((_resolve, reject) => {
              options.signal.addEventListener("abort", () => {
                const err = new DOMException(
                  "The operation was aborted.",
                  "AbortError",
                );
                reject(err);
              });
            });
          },
        );
      vi.stubGlobal("fetch", fetchMock);

      const mod = await import("./http-recognition.js");
      const service = new mod.HttpRecognitionService();
      const blob = createTestBlob("fake image", "image/jpeg");

      try {
        await service.analyse(blob);
        expect.unreachable("should have thrown");
      } catch (err) {
        expectRecognitionError(err, "TIMEOUT");
      }
    }, 10000);

    it("uses RECOGNITION_TIMEOUT_MS env var (default 10000)", async () => {
      vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
      vi.stubEnv("RECOGNITION_MODEL", "llava");
      // Don't set RECOGNITION_TIMEOUT_MS — should default to 10000

      let capturedSignal: AbortSignal | undefined;
      const fetchMock = vi
        .fn()
        .mockImplementation(
          (_url: string, options: { signal: AbortSignal }) => {
            capturedSignal = options.signal;
            return Promise.resolve({
              ok: true,
              json: () => Promise.resolve(validResponse),
            });
          },
        );
      vi.stubGlobal("fetch", fetchMock);

      const mod = await import("./http-recognition.js");
      const service = new mod.HttpRecognitionService();
      const blob = createTestBlob("fake image", "image/jpeg");
      await service.analyse(blob);

      // The signal should have been passed (AbortController was used)
      expect(capturedSignal).toBeDefined();
      // Signal should not be aborted since we responded immediately
      expect(capturedSignal!.aborted).toBe(false);
    });
  });
});
