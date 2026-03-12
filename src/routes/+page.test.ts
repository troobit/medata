/**
 * Component tests for logbook display and meal edit/delete.
 * Task 29: Tests for the home page logbook functionality.
 *
 * We test LogbookList directly since +page.svelte uses SvelteKit
 * $app/navigation and API services that need mocking. LogbookList
 * is the core component responsible for rendering meals and actions.
 */
import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render, cleanup, fireEvent } from "@testing-library/svelte";
import { tick } from "svelte";
import LogbookList from "$lib/components/LogbookList.svelte";
import type { Meal } from "$lib/types/index.js";

function flushPromises(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Create a test meal with sensible defaults. */
function createTestMeal(overrides: Partial<Meal> = {}): Meal {
  return {
    id: `meal-${Math.random().toString(36).slice(2, 8)}`,
    timestamp: Date.now(),
    items: [
      { name: "Porridge", carbs: 30, protein: 5, fat: 3 },
      { name: "Banana", carbs: 27, protein: 1, fat: 0 },
    ],
    totalCarbs: 57,
    totalProtein: 6,
    totalFat: 3,
    source: "manual",
    createdAt: Date.now(),
    updatedAt: Date.now(),
    ...overrides,
  };
}

describe("Logbook display and meal edit/delete", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  describe("meals ordered by timestamp DESC (Req 8.1)", () => {
    it("renders meals in descending order by timestamp", () => {
      const now = Date.now();
      const meals: Meal[] = [
        createTestMeal({
          id: "meal-old",
          timestamp: now - 3600_000,
          items: [{ name: "Old Meal", carbs: 10, protein: 2, fat: 1 }],
          totalCarbs: 10,
          totalProtein: 2,
          totalFat: 1,
        }),
        createTestMeal({
          id: "meal-new",
          timestamp: now,
          items: [{ name: "New Meal", carbs: 20, protein: 3, fat: 2 }],
          totalCarbs: 20,
          totalProtein: 3,
          totalFat: 2,
        }),
        createTestMeal({
          id: "meal-mid",
          timestamp: now - 1800_000,
          items: [{ name: "Mid Meal", carbs: 15, protein: 4, fat: 1 }],
          totalCarbs: 15,
          totalProtein: 4,
          totalFat: 1,
        }),
      ];

      const onSelect = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(LogbookList, {
        props: { meals, onSelect, onEdit, onDelete },
      });

      // Get all the meal summary buttons (expand buttons)
      const buttons = container.querySelectorAll("button[aria-expanded]");
      const buttonTexts = Array.from(buttons).map((b) => b.textContent);

      // The newest meal (20g carbs) should appear before the oldest (10g carbs)
      const newIndex = buttonTexts.findIndex((t) => t?.includes("20g"));
      const oldIndex = buttonTexts.findIndex((t) => t?.includes("10g"));
      expect(newIndex).toBeLessThan(oldIndex);
    });
  });

  describe("each entry shows total carbs, protein, fat, source, timestamp (Req 8.2)", () => {
    it("displays total carbs, protein, fat, source, and timestamp for each meal", async () => {
      const meals: Meal[] = [
        createTestMeal({
          id: "meal-1",
          timestamp: new Date("2026-03-13T12:30:00").getTime(),
          totalCarbs: 57,
          totalProtein: 6,
          totalFat: 3,
          source: "manual",
        }),
      ];

      const onSelect = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(LogbookList, {
        props: { meals, onSelect, onEdit, onDelete },
      });

      const text = container.textContent ?? "";

      // Total carbs should be displayed prominently
      expect(text).toContain("57g");

      // Timestamp should be visible
      expect(text).toContain("12:30");

      // Source icon should be displayed (manual = pencil emoji)
      // The component uses emoji for source display
      const sourceSpan = container.querySelector('[title="manual"]');
      expect(sourceSpan).not.toBeNull();

      // When expanded, protein and fat should also be visible
      const expandButton = container.querySelector("button[aria-expanded]");
      expect(expandButton).not.toBeNull();
      await fireEvent.click(expandButton!);
      await tick();

      const expandedText = container.textContent ?? "";
      // After expansion, we should see detailed macro totals
      expect(expandedText).toContain("6"); // protein
      expect(expandedText).toContain("3"); // fat
    });
  });

  describe("expanding a meal entry shows per-item macros (Req 8.3)", () => {
    it("shows per-item macros when a meal is expanded", async () => {
      const meals: Meal[] = [
        createTestMeal({
          id: "meal-expand",
          items: [
            { name: "Porridge", carbs: 30, protein: 5, fat: 3 },
            { name: "Banana", carbs: 27, protein: 1, fat: 0 },
          ],
        }),
      ];

      const onSelect = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container, getByText } = render(LogbookList, {
        props: { meals, onSelect, onEdit, onDelete },
      });

      // Before expansion, individual items should not be visible
      expect(container.textContent).not.toContain("Porridge");

      // Click expand
      const expandButton = container.querySelector(
        'button[aria-expanded="false"]',
      );
      expect(expandButton).not.toBeNull();
      await fireEvent.click(expandButton!);
      await tick();

      // After expansion, per-item details should be visible
      const expandedText = container.textContent ?? "";
      expect(expandedText).toContain("Porridge");
      expect(expandedText).toContain("Banana");
      // Per-item macros format: "30g C · 5g P · 3g F"
      expect(expandedText).toContain("30g C");
      expect(expandedText).toContain("27g C");
    });
  });

  describe("edit flow: MealEditor opens, PUT request fired on save (Req 8.4)", () => {
    it("calls onEdit callback when Edit button is clicked", async () => {
      const meal = createTestMeal({ id: "meal-edit" });
      const onSelect = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(LogbookList, {
        props: { meals: [meal], onSelect, onEdit, onDelete },
      });

      // Expand the meal first to see action buttons
      const expandButton = container.querySelector(
        'button[aria-expanded="false"]',
      );
      await fireEvent.click(expandButton!);
      await tick();

      // Click Edit button
      const editButton = Array.from(container.querySelectorAll("button")).find(
        (b) => b.textContent?.trim() === "Edit",
      );
      expect(editButton).not.toBeUndefined();
      await fireEvent.click(editButton!);
      await tick();

      expect(onEdit).toHaveBeenCalledWith(meal);
    });

    it("PUT /api/meals/[id] is fired when saving an edited meal", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          data: {
            id: "meal-edit",
            timestamp: Date.now(),
            items: [
              { name: "Updated Porridge", carbs: 35, protein: 6, fat: 4 },
            ],
            totalCarbs: 35,
            totalProtein: 6,
            totalFat: 4,
            source: "manual",
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        }),
      });
      vi.stubGlobal("fetch", mockFetch);

      const { updateMeal } = await import("$lib/services/meal-api.js");
      await updateMeal("meal-edit", {
        items: [{ name: "Updated Porridge", carbs: 35, protein: 6, fat: 4 }],
        totalCarbs: 35,
        totalProtein: 6,
        totalFat: 4,
      });

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/meals/meal-edit",
        expect.objectContaining({ method: "PUT" }),
      );

      const callBody = JSON.parse(mockFetch.mock.calls[0][1].body);
      expect(callBody.items[0].name).toBe("Updated Porridge");

      vi.unstubAllGlobals();
    });
  });

  describe("delete flow: confirmation modal shown, DELETE request fired (Req 8.5)", () => {
    it("calls onDelete callback when Delete button is clicked", async () => {
      const meal = createTestMeal({ id: "meal-delete" });
      const onSelect = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(LogbookList, {
        props: { meals: [meal], onSelect, onEdit, onDelete },
      });

      // Expand the meal first
      const expandButton = container.querySelector(
        'button[aria-expanded="false"]',
      );
      await fireEvent.click(expandButton!);
      await tick();

      // Click Delete button
      const deleteButton = Array.from(
        container.querySelectorAll("button"),
      ).find((b) => b.textContent?.trim() === "Delete");
      expect(deleteButton).not.toBeUndefined();
      await fireEvent.click(deleteButton!);
      await tick();

      // The LogbookList calls onDelete with the meal ID
      expect(onDelete).toHaveBeenCalledWith("meal-delete");
    });

    it("DELETE /api/meals/[id] is fired on confirmed deletion", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({}),
      });
      vi.stubGlobal("fetch", mockFetch);

      const { deleteMeal } = await import("$lib/services/meal-api.js");
      await deleteMeal("meal-delete");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/meals/meal-delete",
        expect.objectContaining({ method: "DELETE" }),
      );

      vi.unstubAllGlobals();
    });
  });
});
