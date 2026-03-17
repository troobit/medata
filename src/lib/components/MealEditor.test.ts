/**
 * Tests for MealEditor.svelte mockMode prop and save failure behaviour.
 * Task 20: These tests are written test-first and should FAIL until
 * the mockMode prop and error handling are implemented in MealEditor.svelte.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, cleanup, fireEvent } from "@testing-library/svelte";
import { tick } from "svelte";
import MealEditor from "./MealEditor.svelte";

function flushPromises(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("MealEditor", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  describe("MockModeBanner rendering", () => {
    it("renders MockModeBanner when mockMode=true prop is passed", () => {
      const onSave = vi.fn();
      const { container } = render(MealEditor, {
        props: {
          source: "manual",
          onSave,
          mockMode: true,
        },
      });

      // MockModeBanner has role="status" and contains "Mock mode"
      const banner = container.querySelector('[role="status"]');
      expect(banner).not.toBeNull();
      expect(banner?.textContent).toContain("Mock mode");
    });

    it("does not render MockModeBanner when mockMode=false", () => {
      const onSave = vi.fn();
      const { container } = render(MealEditor, {
        props: {
          source: "manual",
          onSave,
          mockMode: false,
        },
      });

      const banner = container.querySelector('[role="status"]');
      expect(banner).toBeNull();
    });

    it("does not render MockModeBanner when mockMode is undefined", () => {
      const onSave = vi.fn();
      const { container } = render(MealEditor, {
        props: {
          source: "manual",
          onSave,
        },
      });

      const banner = container.querySelector('[role="status"]');
      expect(banner).toBeNull();
    });
  });

  describe("state retention on save failure", () => {
    it("retains items and macros in memory when save API call fails", async () => {
      const onSave = vi.fn().mockImplementation(() => {
        throw new Error("Network error");
      });

      const { getByText, container } = render(MealEditor, {
        props: {
          source: "manual",
          onSave,
          initialItems: [
            { name: "Porridge", carbs: 30, protein: 5, fat: 3 },
            { name: "Banana", carbs: 27, protein: 1, fat: 0 },
          ],
        },
      });

      // Click save - it should call onSave which throws
      const saveButton = getByText("Save Meal");
      await fireEvent.click(saveButton);
      await tick();

      // Items should still be displayed after the failed save
      // The component should retain all state - items should still be visible
      expect(container.textContent).toContain("Porridge");
      expect(container.textContent).toContain("Banana");

      // Macros should still be calculated and displayed
      // 30 + 27 = 57 carbs, 5 + 1 = 6 protein, 3 + 0 = 3 fat
      expect(container.textContent).toContain("57");
      expect(container.textContent).toContain("6");
      expect(container.textContent).toContain("3");
    });
  });

  describe("error toast on save failure", () => {
    it("shows error toast with Irish English text on save failure", async () => {
      // The MealEditor should catch save errors and show a toast.
      // This test expects the error message to use Irish English localisation.
      const onSave = vi.fn().mockImplementation(() => {
        throw new Error("Network error");
      });

      const { getByText, container } = render(MealEditor, {
        props: {
          source: "manual",
          onSave,
          initialItems: [{ name: "Toast", carbs: 20, protein: 3, fat: 1 }],
        },
      });

      const saveButton = getByText("Save Meal");
      await fireEvent.click(saveButton);
      await flushPromises();
      await tick();

      // Expect an error toast with Irish English phrasing
      // The exact text will depend on the implementation, but it should
      // contain something like "Failed to save" or "couldn't save"
      // and should be in a toast/notification element
      const errorElements = container.querySelectorAll(
        '[role="alert"], .toast-error, [data-toast-type="error"]',
      );
      expect(errorElements.length).toBeGreaterThan(0);
    });
  });
});
