<script lang="ts">
  /**
   * Workstream D: Manual BSL Entry
   * Branch: dev-4
   *
   * Manual blood sugar level entry with stepper input.
   * Supports both finger prick and CGM readings.
   */
  import { goto } from '$app/navigation';
  import { Button } from '$lib/components/ui';
  import { eventsStore, settingsStore } from '$lib/stores';
  import type { BSLUnit } from '$lib/types';

  // BSL value in mmol/L (internal representation)
  let bslValue = $state(5.5);
  let unit = $state<BSLUnit>(settingsStore.settings.defaultBSLUnit);
  let isFingerPrick = $state(false);
  let saving = $state(false);
  let recentValues = $state<number[]>([]);

  // Conversion constants
  const MMOL_TO_MGDL = 18.0182;

  // Load recent BSL values on mount
  $effect(() => {
    loadRecentValues();
  });

  async function loadRecentValues() {
    recentValues = await eventsStore.getRecentBSLValues(4);
  }

  // Display value based on selected unit
  const displayValue = $derived(unit === 'mmol/L' ? bslValue : Math.round(bslValue * MMOL_TO_MGDL));

  // Step sizes based on unit
  const smallStep = $derived(unit === 'mmol/L' ? 0.1 : 1);
  const largeStep = $derived(unit === 'mmol/L' ? 0.5 : 10);

  // Valid range (2-30 mmol/L or 36-540 mg/dL)
  const minValue = $derived(unit === 'mmol/L' ? 2 : 36);
  const maxValue = $derived(unit === 'mmol/L' ? 30 : 540);

  function increment(amount: number) {
    const increment = unit === 'mmol/L' ? amount : amount / MMOL_TO_MGDL;
    bslValue = Math.min(30, Math.max(2, bslValue + increment));
  }

  function decrement(amount: number) {
    const decrement = unit === 'mmol/L' ? amount : amount / MMOL_TO_MGDL;
    bslValue = Math.max(2, bslValue - decrement);
  }

  function setFromDisplay(displayVal: number) {
    if (unit === 'mmol/L') {
      bslValue = Math.min(30, Math.max(2, displayVal));
    } else {
      bslValue = Math.min(30, Math.max(2, displayVal / MMOL_TO_MGDL));
    }
  }

  function selectRecentValue(value: number) {
    bslValue = value;
  }

  async function save() {
    if (bslValue < 2 || bslValue > 30) return;

    saving = true;
    try {
      await eventsStore.logBSL(bslValue, unit, undefined, {
        isFingerPrick,
        source: 'manual'
      });
      await settingsStore.update({ defaultBSLUnit: unit });
      goto('/');
    } catch {
      // Error is shown via store
    } finally {
      saving = false;
    }
  }

  // Format display value appropriately
  function formatValue(val: number): string {
    if (unit === 'mmol/L') {
      return val.toFixed(1);
    }
    return Math.round(val * MMOL_TO_MGDL).toString();
  }
</script>

<svelte:head>
  <title>Log BSL - MeData</title>
</svelte:head>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-8">
    <a href="/log" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
      <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back
    </a>
    <h1 class="text-2xl font-bold text-white">Log Blood Sugar</h1>
  </header>

  <div class="flex flex-1 flex-col">
    <!-- Unit Toggle -->
    <div class="mb-8">
      <span id="unit-label" class="mb-2 block text-sm font-medium text-gray-400">Unit</span>
      <div class="grid grid-cols-2 gap-2" role="group" aria-labelledby="unit-label">
        <button
          type="button"
          class="rounded-lg px-4 py-3 text-center font-medium transition-colors {unit === 'mmol/L'
            ? 'bg-yellow-500 text-white'
            : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
          onclick={() => (unit = 'mmol/L')}
        >
          mmol/L
        </button>
        <button
          type="button"
          class="rounded-lg px-4 py-3 text-center font-medium transition-colors {unit === 'mg/dL'
            ? 'bg-yellow-500 text-white'
            : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
          onclick={() => (unit = 'mg/dL')}
        >
          mg/dL
        </button>
      </div>
    </div>

    <!-- BSL Input with stepper controls -->
    <div class="mb-8 flex-1">
      <label for="bsl-input" class="mb-2 block text-sm font-medium text-gray-400">Blood Sugar</label
      >
      <div class="flex items-center justify-center gap-3">
        <!-- Large decrement button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => decrement(largeStep)}
          disabled={displayValue <= minValue + largeStep}
          aria-label="Decrease by {largeStep} {unit}"
        >
          -{unit === 'mmol/L' ? '0.5' : '10'}
        </button>
        <!-- Small decrement button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => decrement(smallStep)}
          disabled={displayValue <= minValue}
          aria-label="Decrease by {smallStep} {unit}"
        >
          -
        </button>
        <div class="w-28 text-center">
          <input
            id="bsl-input"
            type="number"
            value={displayValue}
            oninput={(e) => setFromDisplay(parseFloat(e.currentTarget.value) || 0)}
            min={minValue}
            max={maxValue}
            step={smallStep}
            class="w-full bg-transparent text-center text-5xl font-bold text-white focus:outline-none"
          />
          <span class="text-sm text-gray-400">{unit}</span>
        </div>
        <!-- Small increment button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => increment(smallStep)}
          disabled={displayValue >= maxValue}
          aria-label="Increase by {smallStep} {unit}"
        >
          +
        </button>
        <!-- Large increment button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => increment(largeStep)}
          disabled={displayValue >= maxValue - largeStep}
          aria-label="Increase by {largeStep} {unit}"
        >
          +{unit === 'mmol/L' ? '0.5' : '10'}
        </button>
      </div>
    </div>

    <!-- Finger Prick Toggle -->
    <div class="mb-8">
      <label
        class="flex cursor-pointer items-center justify-between rounded-lg bg-gray-800 px-4 py-3"
      >
        <div>
          <span class="font-medium text-white">Finger Prick Reading</span>
          <p class="text-sm text-gray-400">Higher accuracy than CGM</p>
        </div>
        <input
          type="checkbox"
          bind:checked={isFingerPrick}
          class="h-5 w-5 rounded border-gray-600 bg-gray-700 text-yellow-500 focus:ring-yellow-500"
        />
      </label>
    </div>

    <!-- Recent Values -->
    {#if recentValues.length > 0}
      <div class="mb-8">
        <span id="recent-values-label" class="mb-2 block text-sm font-medium text-gray-400">
          Recent readings
        </span>
        <div class="flex flex-wrap gap-2" role="group" aria-labelledby="recent-values-label">
          {#each recentValues as value (value)}
            <button
              type="button"
              class="rounded-full px-4 py-2 text-sm font-medium transition-colors {bslValue ===
              value
                ? 'bg-yellow-500 text-white'
                : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
              onclick={() => selectRecentValue(value)}
            >
              {formatValue(value)}
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
      disabled={bslValue < 2 || bslValue > 30}
      loading={saving}
    >
      Log {formatValue(bslValue)}
      {unit}
      {isFingerPrick ? '(finger prick)' : ''}
    </Button>
  </div>
</div>
