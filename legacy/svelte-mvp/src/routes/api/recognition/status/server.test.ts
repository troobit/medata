/**
 * Unit tests for /api/recognition/status endpoint.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("/api/recognition/status GET", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("returns { configured: true, mockMode: false } when base URL and model are set", async () => {
    vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
    vi.stubEnv("RECOGNITION_MODEL", "llava");
    vi.stubEnv("RECOGNITION_MOCK_MODE", "false");

    const { GET } = await import("./+server.js");
    const response = await GET();
    const body = await response.json();

    expect(body.configured).toBe(true);
    expect(body.mockMode).toBe(false);
  });

  it("returns { configured: false, mockMode: false } when base URL is missing", async () => {
    vi.stubEnv("RECOGNITION_BASE_URL", "");
    vi.stubEnv("RECOGNITION_MODEL", "llava");
    vi.stubEnv("RECOGNITION_MOCK_MODE", "false");

    const { GET } = await import("./+server.js");
    const response = await GET();
    const body = await response.json();

    expect(body.configured).toBe(false);
    expect(body.mockMode).toBe(false);
  });

  it("returns { configured: false, mockMode: false } when model is missing", async () => {
    vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
    vi.stubEnv("RECOGNITION_MODEL", "");
    vi.stubEnv("RECOGNITION_MOCK_MODE", "false");

    const { GET } = await import("./+server.js");
    const response = await GET();
    const body = await response.json();

    expect(body.configured).toBe(false);
    expect(body.mockMode).toBe(false);
  });

  it("returns { configured: true, mockMode: true } when RECOGNITION_MOCK_MODE=true", async () => {
    vi.stubEnv("RECOGNITION_MOCK_MODE", "true");

    const { GET } = await import("./+server.js");
    const response = await GET();
    const body = await response.json();

    expect(body.configured).toBe(true);
    expect(body.mockMode).toBe(true);
  });

  it("returns { configured: false, mockMode: false } when service constructor throws", async () => {
    // Mock createRecognitionService to throw
    vi.doMock("$lib/services/recognition.js", () => ({
      createRecognitionService: () => {
        throw new Error("constructor failure");
      },
    }));

    const { GET } = await import("./+server.js");
    const response = await GET();
    const body = await response.json();

    expect(body.configured).toBe(false);
    expect(body.mockMode).toBe(false);
  });
});
