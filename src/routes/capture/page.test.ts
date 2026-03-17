/**
 * Component tests for capture page status detection and conditional rendering.
 * Task 22: Tests for the /capture page recognition status flow.
 *
 * These tests are written test-first and should FAIL until the capture page
 * implements status detection logic (fetching GET /api/recognition/status
 * on mount and conditionally rendering based on the response).
 *
 * The capture page should:
 * - Fetch GET /api/recognition/status on mount
 * - Show a skeleton/loading state while the request is in-flight
 * - Show ManualEntryCTA when { configured: false, mockMode: false }
 * - Show MockModeBanner when { configured: true, mockMode: true }
 * - Show the recognition/camera path when { configured: true, mockMode: false }
 * - Default to ManualEntryCTA on fetch error
 */
import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render, cleanup, waitFor } from "@testing-library/svelte";
import { tick } from "svelte";

function flushPromises(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * We render the capture page directly. Since it uses SvelteKit imports,
 * we mock fetch globally to intercept the /api/recognition/status call.
 */
import CapturePage from "./+page.svelte";

describe("Capture page status detection and conditional rendering", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  describe("skeleton/loading state while status is in-flight", () => {
    it("shows a loading/skeleton state while /api/recognition/status is pending", async () => {
      // Never resolve the fetch so the component stays in loading state
      fetchSpy.mockReturnValue(new Promise(() => {}));

      const { container } = render(CapturePage);
      await tick();

      // The page should show a loading indicator (skeleton) while awaiting status
      // Look for a common loading pattern: aria-busy, role="status", or skeleton class
      const hasLoadingIndicator =
        container.querySelector('[aria-busy="true"]') !== null ||
        container.querySelector(".animate-pulse") !== null ||
        container.querySelector('[data-testid="status-loading"]') !== null ||
        container.textContent?.includes("Loading");

      expect(hasLoadingIndicator).toBe(true);

      // It should NOT yet show ManualEntryCTA or camera components
      expect(container.textContent).not.toContain(
        "Food recognition is not configured",
      );
    });
  });

  describe("ManualEntryCTA when configured=false, mockMode=false", () => {
    it("renders ManualEntryCTA when status returns { configured: false, mockMode: false }", async () => {
      fetchSpy.mockResolvedValue({
        ok: true,
        json: async () => ({ configured: false, mockMode: false }),
      });

      const { container } = render(CapturePage);
      await tick();
      await flushPromises();
      await tick();

      // ManualEntryCTA contains "Food recognition is not configured"
      await waitFor(() => {
        expect(container.textContent).toContain(
          "Food recognition is not configured",
        );
      });

      // It should have a link to /manual
      const manualLink = container.querySelector('a[href="/manual"]');
      expect(manualLink).not.toBeNull();
      expect(manualLink?.textContent).toContain("Enter meal manually");
    });
  });

  describe("MockModeBanner when configured=true, mockMode=true", () => {
    it("renders MockModeBanner when status returns { configured: true, mockMode: true }", async () => {
      fetchSpy.mockResolvedValue({
        ok: true,
        json: async () => ({ configured: true, mockMode: true }),
      });

      const { container } = render(CapturePage);
      await tick();
      await flushPromises();
      await tick();

      // MockModeBanner has role="status" and contains "Mock mode"
      await waitFor(() => {
        const banner = container.querySelector('[role="status"]');
        expect(banner).not.toBeNull();
        expect(banner?.textContent).toContain("Mock mode");
      });
    });
  });

  describe("recognition path when configured=true, mockMode=false", () => {
    it("renders the camera/recognition UI when status returns { configured: true, mockMode: false }", async () => {
      fetchSpy.mockResolvedValue({
        ok: true,
        json: async () => ({ configured: true, mockMode: false }),
      });

      const { container } = render(CapturePage);
      await tick();
      await flushPromises();
      await tick();

      // When configured, the page should show the CameraCapture component
      // (the capture flow), not the ManualEntryCTA
      await waitFor(() => {
        // Should NOT show ManualEntryCTA
        expect(container.textContent).not.toContain(
          "Food recognition is not configured",
        );

        // Should NOT show MockModeBanner
        const banner = container.querySelector('[role="status"]');
        expect(banner).toBeNull();
      });

      // The CameraCapture component should be rendered (the recognition path)
      // CameraCapture renders a video element or camera-related UI
      const hasCameraUI =
        container.querySelector("video") !== null ||
        container.querySelector('[data-testid="camera-capture"]') !== null ||
        container.textContent?.includes("Take Photo") ||
        container.textContent?.includes("Gallery");

      expect(hasCameraUI).toBe(true);
    });
  });

  describe("ManualEntryCTA as safe default on fetch error", () => {
    it("renders ManualEntryCTA when /api/recognition/status request fails", async () => {
      fetchSpy.mockRejectedValue(new Error("Network error"));

      const { container } = render(CapturePage);
      await tick();
      await flushPromises();
      await tick();

      // On error, should fall back to ManualEntryCTA (safe default)
      await waitFor(() => {
        expect(container.textContent).toContain(
          "Food recognition is not configured",
        );
      });

      const manualLink = container.querySelector('a[href="/manual"]');
      expect(manualLink).not.toBeNull();
    });

    it("renders ManualEntryCTA when /api/recognition/status returns non-ok response", async () => {
      fetchSpy.mockResolvedValue({
        ok: false,
        status: 500,
        json: async () => ({ error: "Internal server error" }),
      });

      const { container } = render(CapturePage);
      await tick();
      await flushPromises();
      await tick();

      // On non-ok response, should fall back to ManualEntryCTA (safe default)
      await waitFor(() => {
        expect(container.textContent).toContain(
          "Food recognition is not configured",
        );
      });

      const manualLink = container.querySelector('a[href="/manual"]');
      expect(manualLink).not.toBeNull();
    });
  });

  describe("fetch is called correctly", () => {
    it("calls GET /api/recognition/status on mount", async () => {
      fetchSpy.mockResolvedValue({
        ok: true,
        json: async () => ({ configured: false, mockMode: false }),
      });

      render(CapturePage);
      await tick();
      await flushPromises();
      await tick();

      expect(fetchSpy).toHaveBeenCalledWith("/api/recognition/status");
    });
  });
});
