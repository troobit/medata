/**
 * Component tests for preset save, apply, edit, and delete.
 * Task 30: Tests for the /presets page functionality.
 *
 * We test PresetList component directly for display and action callbacks,
 * and test the API service functions for the HTTP request verification.
 */
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, cleanup, fireEvent } from "@testing-library/svelte";
import { tick } from "svelte";
import PresetList from "$lib/components/PresetList.svelte";
import type { Preset, FoodItem } from "$lib/types/index.js";

function flushPromises(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Create a test preset with sensible defaults. */
function createTestPreset(overrides: Partial<Preset> = {}): Preset {
  return {
    id: `preset-${Math.random().toString(36).slice(2, 8)}`,
    name: "Test Preset",
    category: "meal",
    items: [
      { name: "Porridge", carbs: 30, protein: 5, fat: 3 },
      { name: "Banana", carbs: 27, protein: 1, fat: 0 },
    ],
    totalCarbs: 57,
    totalProtein: 6,
    totalFat: 3,
    createdAt: Date.now(),
    updatedAt: Date.now(),
    ...overrides,
  };
}

describe("Preset save, apply, edit, and delete", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  describe("save as preset: POST /api/presets with name and category (Req 9.1)", () => {
    it("POST /api/presets sends correct payload with name and category", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          data: {
            id: "preset-new",
            name: "Morning Oats",
            category: "meal",
            items: [{ name: "Porridge", carbs: 30, protein: 5, fat: 3 }],
            totalCarbs: 30,
            totalProtein: 5,
            totalFat: 3,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        }),
      });
      vi.stubGlobal("fetch", mockFetch);

      const { createPreset } = await import("$lib/services/preset-api.js");
      await createPreset({
        name: "Morning Oats",
        category: "meal",
        items: [{ name: "Porridge", carbs: 30, protein: 5, fat: 3 }],
      });

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/presets",
        expect.objectContaining({ method: "POST" }),
      );

      const body = JSON.parse(mockFetch.mock.calls[0][1].body);
      expect(body.name).toBe("Morning Oats");
      expect(body.category).toBe("meal");
      expect(body.items).toHaveLength(1);

      vi.unstubAllGlobals();
    });
  });

  describe("presets page: presets grouped by meal/snack category (Req 9.2)", () => {
    it("groups presets by meal and snack category", () => {
      const presets: Preset[] = [
        createTestPreset({ id: "p1", name: "Full Irish", category: "meal" }),
        createTestPreset({ id: "p2", name: "Apple", category: "snack" }),
        createTestPreset({ id: "p3", name: "Pasta Bake", category: "meal" }),
        createTestPreset({ id: "p4", name: "Yoghurt", category: "snack" }),
      ];

      const onApply = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(PresetList, {
        props: { presets, onApply, onEdit, onDelete },
      });

      const text = container.textContent ?? "";

      // Should show category headers
      expect(text).toContain("Meals");
      expect(text).toContain("Snacks");

      // All preset names should be visible
      expect(text).toContain("Full Irish");
      expect(text).toContain("Apple");
      expect(text).toContain("Pasta Bake");
      expect(text).toContain("Yoghurt");

      // Verify the "Meals" header appears before "Snacks" header
      const mealsIdx = text.indexOf("Meals");
      const snacksIdx = text.indexOf("Snacks");
      expect(mealsIdx).toBeLessThan(snacksIdx);
    });
  });

  describe("apply preset: POST /api/meals with source: preset (Req 9.3)", () => {
    it("calls onApply when a preset card is clicked", async () => {
      const preset = createTestPreset({ id: "p-apply", name: "Quick Oats" });
      const onApply = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(PresetList, {
        props: { presets: [preset], onApply, onEdit, onDelete },
      });

      // Click on the preset card (it's a div with role="button")
      const card = container.querySelector('[role="button"]');
      expect(card).not.toBeNull();
      await fireEvent.click(card!);
      await tick();

      expect(onApply).toHaveBeenCalledWith(preset);
    });

    it("POST /api/meals sends payload with source: preset when applying a preset", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          data: {
            id: "meal-from-preset",
            timestamp: Date.now(),
            items: [{ name: "Porridge", carbs: 30, protein: 5, fat: 3 }],
            totalCarbs: 30,
            totalProtein: 5,
            totalFat: 3,
            source: "preset",
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        }),
      });
      vi.stubGlobal("fetch", mockFetch);

      const { createMeal } = await import("$lib/services/meal-api.js");
      await createMeal({
        timestamp: Date.now(),
        items: [{ name: "Porridge", carbs: 30, protein: 5, fat: 3 }],
        totalCarbs: 30,
        totalProtein: 5,
        totalFat: 3,
        source: "preset",
      });

      const body = JSON.parse(mockFetch.mock.calls[0][1].body);
      expect(body.source).toBe("preset");

      vi.unstubAllGlobals();
    });
  });

  describe("edit preset: PUT /api/presets/[id] with updated fields (Req 9.4)", () => {
    it("calls onEdit when edit button is clicked on a preset card", async () => {
      const preset = createTestPreset({
        id: "p-edit",
        name: "Editable Preset",
      });
      const onApply = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(PresetList, {
        props: { presets: [preset], onApply, onEdit, onDelete },
      });

      // Click the edit button (has aria-label="Edit preset")
      const editButton = container.querySelector('[aria-label="Edit preset"]');
      expect(editButton).not.toBeNull();
      await fireEvent.click(editButton!);
      await tick();

      expect(onEdit).toHaveBeenCalledWith(preset);
      // Ensure onApply was NOT called (stopPropagation)
      expect(onApply).not.toHaveBeenCalled();
    });

    it("PUT /api/presets/[id] sends updated fields", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          data: {
            id: "p-edit",
            name: "Updated Name",
            category: "snack",
            items: [{ name: "Porridge", carbs: 30, protein: 5, fat: 3 }],
            totalCarbs: 30,
            totalProtein: 5,
            totalFat: 3,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        }),
      });
      vi.stubGlobal("fetch", mockFetch);

      const { updatePreset } = await import("$lib/services/preset-api.js");
      await updatePreset("p-edit", {
        name: "Updated Name",
        category: "snack",
      });

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/presets/p-edit",
        expect.objectContaining({ method: "PUT" }),
      );

      const body = JSON.parse(mockFetch.mock.calls[0][1].body);
      expect(body.name).toBe("Updated Name");
      expect(body.category).toBe("snack");

      vi.unstubAllGlobals();
    });
  });

  describe("delete preset: DELETE /api/presets/[id] after confirmation (Req 9.4)", () => {
    it("calls onDelete when delete button is clicked on a preset card", async () => {
      const preset = createTestPreset({
        id: "p-delete",
        name: "Deletable Preset",
      });
      const onApply = vi.fn();
      const onEdit = vi.fn();
      const onDelete = vi.fn();

      const { container } = render(PresetList, {
        props: { presets: [preset], onApply, onEdit, onDelete },
      });

      // Click the delete button (has aria-label="Delete preset")
      const deleteButton = container.querySelector(
        '[aria-label="Delete preset"]',
      );
      expect(deleteButton).not.toBeNull();
      await fireEvent.click(deleteButton!);
      await tick();

      expect(onDelete).toHaveBeenCalledWith(preset);
      // Ensure onApply was NOT called (stopPropagation)
      expect(onApply).not.toHaveBeenCalled();
    });

    it("DELETE /api/presets/[id] is fired on confirmed deletion", async () => {
      const mockFetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({}),
      });
      vi.stubGlobal("fetch", mockFetch);

      const { deletePreset } = await import("$lib/services/preset-api.js");
      await deletePreset("p-delete");

      expect(mockFetch).toHaveBeenCalledWith(
        "/api/presets/p-delete",
        expect.objectContaining({ method: "DELETE" }),
      );

      vi.unstubAllGlobals();
    });
  });
});
