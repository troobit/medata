<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { Button } from '$lib/components/ui';
  import { eventsStore, settingsStore } from '$lib/stores';
  import type { InsulinType } from '$lib/types';

  let units = $state(0);
  let insulinType = $state<InsulinType>(settingsStore.settings.defaultInsulinType);
  let saving = $state(false);
  let recentDoses = $state<number[]>([]);
  let loadingRecent = $state(true);

  // Default quick-select values as fallback when no recent doses exist
  const defaultQuickSelect = [2, 4, 6, 8, 10, 12];

  // Load recent doses when insulin type changes
  async function loadRecentDoses() {
    loadingRecent = true;
    const doses = await eventsStore.getRecentInsulinDoses(insulinType, 6);
    recentDoses = doses;
    loadingRecent = false;
  }

  // React to insulin type changes
  $effect(() => {
    loadRecentDoses();
  });

  onMount(() => {
    loadRecentDoses();
  });

  function adjustUnits(amount: number) {
    const newValue = units + amount;
    if (newValue >= 0 && newValue <= 300) {
      units = newValue;
    }
  }

  async function save() {
    if (units <= 0) return;

    saving = true;
    try {
      await eventsStore.logInsulin(units, insulinType);
      // Update default insulin type for next time
      await settingsStore.update({ defaultInsulinType: insulinType });
      goto('/');
    } catch {
      // Error is shown via store
    } finally {
      saving = false;
    }
  }

  // Use recent doses if available, otherwise fall back to defaults
  const quickSelectValues = $derived(recentDoses.length > 0 ? recentDoses : defaultQuickSelect);
</script>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-8">
    <a href="/log" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
      <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back
    </a>
    <h1 class="text-2xl font-bold text-white">Log Insulin</h1>
  </header>

  <div class="flex flex-1 flex-col">
    <!-- Insulin Type Toggle -->
    <fieldset class="mb-8">
      <legend class="mb-2 block text-sm font-medium text-gray-400">Type</legend>
      <div class="grid grid-cols-2 gap-2">
        <button
          type="button"
          class="rounded-lg px-4 py-3 text-center font-medium transition-colors {insulinType ===
          'bolus'
            ? 'bg-blue-500 text-white'
            : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
          onclick={() => (insulinType = 'bolus')}
        >
          Bolus
        </button>
        <button
          type="button"
          class="rounded-lg px-4 py-3 text-center font-medium transition-colors {insulinType ===
          'basal'
            ? 'bg-blue-500 text-white'
            : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
          onclick={() => (insulinType = 'basal')}
        >
          Basal
        </button>
      </div>
    </fieldset>

    <!-- Units Input with +/-1 and +/-5 adjustments -->
    <div class="mb-6">
      <label for="units-input" class="mb-2 block text-sm font-medium text-gray-400">Units</label>
      <div class="flex items-center justify-center gap-3">
        <!-- -5 button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustUnits(-5)}
          disabled={units < 5}
          aria-label="Decrease units by 5"
        >
          -5
        </button>
        <!-- -1 button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustUnits(-1)}
          disabled={units <= 0}
          aria-label="Decrease units by 1"
        >
          -
        </button>
        <!-- Value display -->
        <div class="w-24 text-center">
          <input
            id="units-input"
            type="number"
            bind:value={units}
            min="0"
            max="300"
            class="w-full bg-transparent text-center text-5xl font-bold text-white focus:outline-none"
            aria-describedby="units-label"
          />
          <span id="units-label" class="text-sm text-gray-400">units</span>
        </div>
        <!-- +1 button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustUnits(1)}
          disabled={units >= 300}
          aria-label="Increase units by 1"
        >
          +
        </button>
        <!-- +5 button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustUnits(5)}
          disabled={units > 295}
          aria-label="Increase units by 5"
        >
          +5
        </button>
      </div>
    </div>

    <!-- Quick Select (recent doses or defaults) -->
    <fieldset class="mb-8 flex-1">
      <legend class="mb-2 block text-sm font-medium text-gray-400">
        {recentDoses.length > 0 ? 'Recent doses' : 'Quick select'}
        {#if loadingRecent}
          <span class="ml-2 text-xs text-gray-500">Loading...</span>
        {/if}
      </legend>
      <div class="flex flex-wrap gap-2">
        {#each quickSelectValues as value}
          <button
            type="button"
            class="rounded-full px-4 py-2 text-sm font-medium transition-colors {units === value
              ? 'bg-blue-500 text-white'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (units = value)}
          >
            {value}
          </button>
        {/each}
      </div>
    </fieldset>

    <!-- Error Display -->
    {#if eventsStore.error}
      <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
        {eventsStore.error}
      </div>
    {/if}

    <!-- Save Button -->
    <Button
      variant="primary"
      size="lg"
      class="w-full"
      onclick={save}
      disabled={units <= 0}
      loading={saving}
    >
      Log {units} units {insulinType}
    </Button>
  </div>
</div>
