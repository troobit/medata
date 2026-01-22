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

  async function loadRecentDoses() {
    recentDoses = await eventsStore.getRecentInsulinDoses(insulinType, 5);
  }

  onMount(() => {
    loadRecentDoses();
  });

  $effect(() => {
    // Reload recent doses when insulin type changes
    loadRecentDoses();
  });

  function increment() {
    if (units < 300) units++;
  }

  function decrement() {
    if (units > 0) units--;
  }

  function adjustBy(amount: number) {
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
    <div class="mb-8">
      <span class="mb-2 block text-sm font-medium text-gray-400">Type</span>
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
    </div>

    <!-- Units Input -->
    <div class="mb-8 flex-1">
      <span class="mb-2 block text-sm font-medium text-gray-400">Units</span>
      <div class="flex items-center justify-center gap-6">
        <button
          type="button"
          class="flex h-16 w-16 items-center justify-center rounded-full bg-gray-800 text-3xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={decrement}
          disabled={units <= 0}
        >
          -
        </button>
        <div class="w-24 text-center">
          <input
            type="number"
            bind:value={units}
            min="0"
            max="300"
            aria-label="Insulin units"
            class="w-full bg-transparent text-center text-5xl font-bold text-white focus:outline-none"
          />
          <span class="text-sm text-gray-400">units</span>
        </div>
        <button
          type="button"
          class="flex h-16 w-16 items-center justify-center rounded-full bg-gray-800 text-3xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={increment}
          disabled={units >= 300}
        >
          +
        </button>
      </div>
    </div>

    <!-- Adjustment Buttons -->
    <div class="mb-6">
      <span class="mb-2 block text-sm font-medium text-gray-400">Adjust</span>
      <div class="flex justify-center gap-4">
        <button
          type="button"
          class="rounded-lg bg-gray-800 px-6 py-3 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-50"
          onclick={() => adjustBy(-5)}
          disabled={units < 5}
        >
          -5
        </button>
        <button
          type="button"
          class="rounded-lg bg-gray-800 px-6 py-3 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => adjustBy(5)}
          disabled={units >= 295}
        >
          +5
        </button>
      </div>
    </div>

    <!-- Recent Doses -->
    <div class="mb-8">
      <span class="mb-2 block text-sm font-medium text-gray-400">
        {recentDoses.length > 0 ? `Recent ${insulinType} doses` : 'Quick select'}
      </span>
      <div class="flex flex-wrap gap-2">
        {#if recentDoses.length > 0}
          {#each recentDoses as value (value)}
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
        {:else}
          {#each [2, 4, 6, 8, 10, 12] as value (value)}
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
        {/if}
      </div>
    </div>

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
