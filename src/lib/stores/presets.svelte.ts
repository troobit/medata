import { getPresetService } from '$lib/services/PresetService';
import type { MealPreset, CreatePresetInput, UpdatePresetInput, MealItem } from '$lib/types';

/**
 * Reactive store for meal presets using Svelte 5 runes
 * Task 25: Meal preset management
 */
function createPresetsStore() {
  let presets = $state<MealPreset[]>([]);
  let loading = $state(false);
  let error = $state<string | null>(null);

  const service = getPresetService();

  async function loadAll() {
    loading = true;
    error = null;
    try {
      presets = await service.getAll();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load presets';
    } finally {
      loading = false;
    }
  }

  async function loadRecent(limit: number = 5) {
    loading = true;
    error = null;
    try {
      presets = await service.getRecent(limit);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load presets';
    } finally {
      loading = false;
    }
  }

  async function search(query: string) {
    if (!query.trim()) {
      await loadAll();
      return;
    }

    loading = true;
    error = null;
    try {
      presets = await service.searchByName(query);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to search presets';
    } finally {
      loading = false;
    }
  }

  async function create(input: CreatePresetInput) {
    loading = true;
    error = null;
    try {
      const preset = await service.create(input);
      presets = [preset, ...presets];
      return preset;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to create preset';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function createFromItems(name: string, items: MealItem[]) {
    loading = true;
    error = null;
    try {
      const preset = await service.createFromItems(name, items);
      presets = [preset, ...presets];
      return preset;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to create preset';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function update(id: string, updates: UpdatePresetInput) {
    loading = true;
    error = null;
    try {
      const updated = await service.update(id, updates);
      presets = presets.map((p) => (p.id === id ? updated : p));
      return updated;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to update preset';
      throw e;
    } finally {
      loading = false;
    }
  }

  async function markUsed(id: string) {
    try {
      await service.markUsed(id);
      // Re-sort presets by updatedAt
      await loadAll();
    } catch (e) {
      // Silent failure - not critical
    }
  }

  async function deletePreset(id: string) {
    loading = true;
    error = null;
    try {
      await service.delete(id);
      presets = presets.filter((p) => p.id !== id);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to delete preset';
      throw e;
    } finally {
      loading = false;
    }
  }

  function getById(id: string): MealPreset | undefined {
    return presets.find((p) => p.id === id);
  }

  return {
    get presets() {
      return presets;
    },
    get loading() {
      return loading;
    },
    get error() {
      return error;
    },
    loadAll,
    loadRecent,
    search,
    create,
    createFromItems,
    update,
    markUsed,
    deletePreset,
    getById
  };
}

export const presetsStore = createPresetsStore();
