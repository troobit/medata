/**
 * Unit tests for createRecognitionService() factory.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("createRecognitionService", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("returns MockRecognitionService when RECOGNITION_MOCK_MODE=true", async () => {
    vi.stubEnv("RECOGNITION_MOCK_MODE", "true");

    const { createRecognitionService } = await import("./recognition.js");
    const service = createRecognitionService();

    expect(service.getBackendType()).toBe("mock");
    expect(service.isReady()).toBe(true);
  });

  it("returns HttpRecognitionService when RECOGNITION_MOCK_MODE=false", async () => {
    vi.stubEnv("RECOGNITION_MOCK_MODE", "false");
    vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
    vi.stubEnv("RECOGNITION_MODEL", "llava");

    const { createRecognitionService } = await import("./recognition.js");
    const service = createRecognitionService();

    expect(service.getBackendType()).toBe("http");
  });

  it("returns HttpRecognitionService when RECOGNITION_MOCK_MODE is unset", async () => {
    // Don't set RECOGNITION_MOCK_MODE
    vi.stubEnv("RECOGNITION_BASE_URL", "http://localhost:11434");
    vi.stubEnv("RECOGNITION_MODEL", "llava");

    const { createRecognitionService } = await import("./recognition.js");
    const service = createRecognitionService();

    expect(service.getBackendType()).toBe("http");
  });
});
