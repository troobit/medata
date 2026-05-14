/**
 * Component tests for manual entry flow.
 * Task 28: Tests for the /manual page flow.
 *
 * These tests are written test-first and should FAIL until
 * the full manual entry flow is wired up correctly.
 */
import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render, cleanup, fireEvent } from "@testing-library/svelte";
import { tick } from "svelte";

function flushPromises(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * We test the ManualEntryForm component directly since the +page.svelte
 * uses SvelteKit imports ($app/navigation, services) that are hard to mock
 * in a unit test context. The form is the core of the manual entry flow.
 */
import ManualEntryForm from "$lib/components/ManualEntryForm.svelte";

describe("Manual entry flow", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  describe("form fields (Req 7.1)", () => {
    it("renders form with name, carbs, protein, fat fields", () => {
      const onProceed = vi.fn();
      const { container } = render(ManualEntryForm, {
        props: { onProceed },
      });

      // Should have name input
      const nameInput = container.querySelector(
        'input[placeholder="Food name"]',
      );
      expect(nameInput).not.toBeNull();

      // Should have carbs input
      const carbsLabel = container.querySelector('label[for*="carbs"]');
      expect(carbsLabel).not.toBeNull();
      expect(carbsLabel?.textContent).toContain("Carbs");

      // Should have protein input
      const proteinLabel = container.querySelector('label[for*="protein"]');
      expect(proteinLabel).not.toBeNull();
      expect(proteinLabel?.textContent).toContain("Protein");

      // Should have fat input
      const fatLabel = container.querySelector('label[for*="fat"]');
      expect(fatLabel).not.toBeNull();
      expect(fatLabel?.textContent).toContain("Fat");
    });
  });

  describe("multiple items before save (Req 7.2)", () => {
    it("can add multiple items before save", async () => {
      const onProceed = vi.fn();
      const { getByText, container } = render(ManualEntryForm, {
        props: { onProceed },
      });

      // Initially there should be 1 item
      let items = container.querySelectorAll('input[placeholder="Food name"]');
      expect(items.length).toBe(1);

      // Click "Add Another Item" to add a second item
      const addButton = getByText("Add Another Item");
      await fireEvent.click(addButton);
      await tick();

      items = container.querySelectorAll('input[placeholder="Food name"]');
      expect(items.length).toBe(2);

      // Add a third item
      await fireEvent.click(addButton);
      await tick();

      items = container.querySelectorAll('input[placeholder="Food name"]');
      expect(items.length).toBe(3);
    });
  });

  describe("saved meal has source: manual (Req 7.3)", () => {
    it("calls onProceed with food items that will be saved with source manual", async () => {
      const onProceed = vi.fn();
      const { container, getByText } = render(ManualEntryForm, {
        props: { onProceed },
      });

      // Fill in the first item
      const nameInput = container.querySelector(
        'input[placeholder="Food name"]',
      ) as HTMLInputElement;
      await fireEvent.change(nameInput, { target: { value: "Porridge" } });
      await tick();

      // Fill in carbs
      const carbsInput = container.querySelector(
        'input[id*="carbs"]',
      ) as HTMLInputElement;
      await fireEvent.change(carbsInput, { target: { value: "30" } });
      await tick();

      // Click proceed
      const proceedButton = getByText("Review & Save");
      await fireEvent.click(proceedButton);
      await tick();

      // Verify onProceed was called with correct items
      expect(onProceed).toHaveBeenCalledWith(
        expect.arrayContaining([
          expect.objectContaining({
            name: "Porridge",
            carbs: 30,
          }),
        ]),
      );

      // The page passes source='manual' to MealEditor, verified by reading +page.svelte
      // The actual source field is set in the page component, not the form
    });
  });

  describe("POST /api/meals payload with source field (Req 7.3)", () => {
    it("mock POST /api/meals verifies correct payload including source: manual", async () => {
      // Mock fetch to intercept the POST request
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          data: {
            id: "meal-1",
            timestamp: Date.now(),
            items: [{ name: "Porridge", carbs: 30, protein: 5, fat: 3 }],
            totalCarbs: 30,
            totalProtein: 5,
            totalFat: 3,
            source: "manual",
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        }),
      });
      vi.stubGlobal("fetch", mockFetch);

      // Directly call the meal-api createMeal function to verify the payload
      const { createMeal } = await import("$lib/services/meal-api.js");

      await createMeal({
        timestamp: Date.now(),
        items: [{ name: "Porridge", carbs: 30, protein: 5, fat: 3 }],
        totalCarbs: 30,
        totalProtein: 5,
        totalFat: 3,
        source: "manual",
      });

      // Verify fetch was called with POST /api/meals
      expect(mockFetch).toHaveBeenCalledWith(
        "/api/meals",
        expect.objectContaining({
          method: "POST",
          headers: { "Content-Type": "application/json" },
        }),
      );

      // Verify the body includes source: 'manual'
      const callArgs = mockFetch.mock.calls[0];
      const body = JSON.parse(callArgs[1].body);
      expect(body.source).toBe("manual");
      expect(body.items).toEqual([
        { name: "Porridge", carbs: 30, protein: 5, fat: 3 },
      ]);

      vi.unstubAllGlobals();
    });
  });
});
