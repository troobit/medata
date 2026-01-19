<script lang="ts">
  import { goto } from '$app/navigation';
  import { Button } from '$lib/components/ui';
  import { eventsStore, settingsStore } from '$lib/stores';
  import type { InsulinType } from '$lib/types';

  let units = $state(0);
  let insulinType = $state<InsulinType>(settingsStore.settings.defaultInsulinType);
  let saving = $state(false);
  let recentDoses = $state<number[]>([]);

  // Load recent doses when insulin type changes
  $effect(() => {
    loadRecentDoses(insulinType);
  });

  async function loadRecentDoses(type: InsulinType) {
    recentDoses = await eventsStore.getRecentInsulinDoses(type, 4);
  }

  function increment(amount: number = 1) {
    units = Math.min(300, Math.max(0, units + amount));
  }

  function decrement(amount: number = 1) {
    units = Math.max(0, units - amount);
  }

  async function save() {
    if (units <= 0) return;

    saving = true;
    try {
      await eventsStore.logInsulin(units, insulinType);
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
      <span id="insulin-type-label" class="mb-2 block text-sm font-medium text-gray-400">Type</span>
      <div class="grid grid-cols-2 gap-2" role="group" aria-labelledby="insulin-type-label">
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

    <!-- Units Input with ±1 and ±5 controls -->
    <div class="mb-8 flex-1">
      <label for="units-input" class="mb-2 block text-sm font-medium text-gray-400">Units</label>
      <div class="flex items-center justify-center gap-3">
        <!-- -5 button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => decrement(5)}
          disabled={units < 5}
          aria-label="Decrease by 5 units"
        >
          -5
        </button>
        <!-- -1 button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => decrement(1)}
          disabled={units <= 0}
          aria-label="Decrease by 1 unit"
        >
          -
        </button>
        <div class="w-24 text-center">
          <input
            id="units-input"
            type="number"
            bind:value={units}
            min="0"
            max="300"
            class="w-full bg-transparent text-center text-5xl font-bold text-white focus:outline-none"
          />
          <span class="text-sm text-gray-400">units</span>
        </div>
        <!-- +1 button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => increment(1)}
          disabled={units >= 300}
          aria-label="Increase by 1 unit"
        >
          +
        </button>
        <!-- +5 button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => increment(5)}
          disabled={units > 295}
          aria-label="Increase by 5 units"
        >
          +5
        </button>
      </div>
    </div>

    <!-- Recent Doses (dynamic based on insulin type) -->
    {#if recentDoses.length > 0}
      <div class="mb-8">
        <span id="recent-doses-label" class="mb-2 block text-sm font-medium text-gray-400">
          Recent {insulinType} doses
        </span>
        <div class="flex flex-wrap gap-2" role="group" aria-labelledby="recent-doses-label">
          {#each recentDoses as dose (dose)}
            <button
              type="button"
              class="rounded-full px-4 py-2 text-sm font-medium transition-colors {units === dose
                ? 'bg-blue-500 text-white'
                : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
              onclick={() => (units = dose)}
            >
              {dose}
            </button>
          {/each}
        </div>
      </div>
    {/if}

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
