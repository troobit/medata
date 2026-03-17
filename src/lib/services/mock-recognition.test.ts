/**
 * Unit tests for MockRecognitionService.
 * Test-first: these tests are written before the implementation.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { MockRecognitionService } from "./mock-recognition.js";
import type { FoodAnalysisResult } from "./recognition.js";

describe("MockRecognitionService", () => {
  let service: MockRecognitionService;

  beforeEach(() => {
    service = new MockRecognitionService();
  });

  it("isReady() returns true", () => {
    expect(service.isReady()).toBe(true);
  });

  it("getBackendType() returns 'mock'", () => {
    expect(service.getBackendType()).toBe("mock");
  });

  it("analyse() returns FoodAnalysisResult matching schema", async () => {
    vi.useFakeTimers();
    const blob = new Blob(["fake image"], { type: "image/png" });
    const promise = service.analyse(blob);
    await vi.advanceTimersByTimeAsync(1500);
    const result: FoodAnalysisResult = await promise;

    // Verify schema structure
    expect(result).toHaveProperty("items");
    expect(result).toHaveProperty("overallConfidence");
    expect(result).toHaveProperty("notes");
    expect(Array.isArray(result.items)).toBe(true);
    expect(typeof result.overallConfidence).toBe("number");

    // Verify each item has correct shape
    for (const item of result.items) {
      expect(item).toHaveProperty("name");
      expect(item).toHaveProperty("carbs");
      expect(item).toHaveProperty("protein");
      expect(item).toHaveProperty("fat");
      expect(item).toHaveProperty("confidence");
      expect(typeof item.name).toBe("string");
      expect(typeof item.carbs).toBe("number");
      expect(typeof item.protein).toBe("number");
      expect(typeof item.fat).toBe("number");
      expect(typeof item.confidence).toBe("number");
    }

    vi.useRealTimers();
  });

  it("result items array has 2-4 entries", async () => {
    vi.useFakeTimers();
    const blob = new Blob(["fake image"], { type: "image/png" });
    const promise = service.analyse(blob);
    await vi.advanceTimersByTimeAsync(1500);
    const result = await promise;

    expect(result.items.length).toBeGreaterThanOrEqual(2);
    expect(result.items.length).toBeLessThanOrEqual(4);

    vi.useRealTimers();
  });

  it("all items have non-negative macro values", async () => {
    vi.useFakeTimers();
    const blob = new Blob(["fake image"], { type: "image/png" });
    const promise = service.analyse(blob);
    await vi.advanceTimersByTimeAsync(1500);
    const result = await promise;

    for (const item of result.items) {
      expect(item.carbs).toBeGreaterThanOrEqual(0);
      expect(item.protein).toBeGreaterThanOrEqual(0);
      expect(item.fat).toBeGreaterThanOrEqual(0);
    }

    vi.useRealTimers();
  });

  it("notes field contains [MOCK] prefix", async () => {
    vi.useFakeTimers();
    const blob = new Blob(["fake image"], { type: "image/png" });
    const promise = service.analyse(blob);
    await vi.advanceTimersByTimeAsync(1500);
    const result = await promise;

    expect(result.notes).toBeDefined();
    expect(result.notes).toMatch(/^\[MOCK\]/);

    vi.useRealTimers();
  });

  it("artificial delay is between 500ms-1500ms", async () => {
    vi.useFakeTimers();
    const blob = new Blob(["fake image"], { type: "image/png" });
    const promise = service.analyse(blob);

    // At 499ms the promise should not have resolved
    await vi.advanceTimersByTimeAsync(499);
    let resolved = false;
    promise.then(() => {
      resolved = true;
    });
    // Flush microtasks
    await vi.advanceTimersByTimeAsync(0);
    expect(resolved).toBe(false);

    // At 1500ms the promise must have resolved
    await vi.advanceTimersByTimeAsync(1001);
    expect(resolved).toBe(true);

    await promise;
    vi.useRealTimers();
  });
});
