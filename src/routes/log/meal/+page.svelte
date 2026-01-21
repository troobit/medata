<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { Button, Input } from '$lib/components/ui';
  import { eventsStore, presetsStore } from '$lib/stores';
  import type { AlcoholType, MealPreset } from '$lib/types';

  let carbs = $state(0);
  let protein = $state<number | undefined>(undefined);
  let fat = $state<number | undefined>(undefined);
  let description = $state('');
  let saving = $state(false);
  let recentCarbs = $state<number[]>([]);
  let loadingRecent = $state(true);

  // Alcohol tracking
  let alcoholUnits = $state<number | undefined>(undefined);
  let alcoholType = $state<AlcoholType | undefined>(undefined);

  // Preset management
  let showSavePreset = $state(false);
  let presetName = $state('');

  // Alcohol type options
  const alcoholTypeOptions: Array<{ value: AlcoholType | ''; label: string }> = [
    { value: '', label: 'Not specified' },
    { value: 'beer', label: 'Beer / Cider' },
    { value: 'wine', label: 'Wine' },
    { value: 'spirit', label: 'Spirits' },
    { value: 'mixed', label: 'Cocktails / Mixed' }
  ];

  // Default quick-select values as fallback when no recent carbs exist
  const defaultCarbQuickSelect = [15, 30, 45, 60, 75, 90];

  // Food icon shortcuts with default carb values
  const foodShortcuts = [
    { icon: '🍞', label: 'Bread', carbs: 15 },
    { icon: '🍕', label: 'Pizza', carbs: 30, fat: 12 },
    { icon: '🍔', label: 'Burger', carbs: 35, protein: 25, fat: 20 },
    { icon: '🍎', label: 'Apple', carbs: 25 },
    { icon: '🍚', label: 'Rice', carbs: 45 }
  ];

  // Drink shortcuts with carbs and alcohol units
  const drinkShortcuts = [
    { icon: '🍺', label: 'Pint', carbs: 12, alcoholUnits: 2.3, alcoholType: 'beer' as AlcoholType },
    { icon: '🍷', label: 'Wine', carbs: 4, alcoholUnits: 2.1, alcoholType: 'wine' as AlcoholType },
    { icon: '🥃', label: 'Spirit', carbs: 0, alcoholUnits: 1, alcoholType: 'spirit' as AlcoholType },
    { icon: '🍹', label: 'Cocktail', carbs: 20, alcoholUnits: 2, alcoholType: 'mixed' as AlcoholType }
  ];

  // Load recent carb values
  async function loadRecentCarbs() {
    loadingRecent = true;
    const values = await eventsStore.getRecentCarbValues(6);
    recentCarbs = values;
    loadingRecent = false;
  }

  onMount(() => {
    loadRecentCarbs();
    presetsStore.loadRecent(5);
  });

  function adjustCarbs(amount: number) {
    const newValue = carbs + amount;
    if (newValue >= 0 && newValue <= 500) {
      carbs = newValue;
    }
  }

  function applyFoodShortcut(food: (typeof foodShortcuts)[0]) {
    carbs = food.carbs;
    if (food.protein) protein = food.protein;
    if (food.fat) fat = food.fat;
    description = food.label;
    // Clear alcohol when selecting food
    alcoholUnits = undefined;
    alcoholType = undefined;
  }

  function applyDrinkShortcut(drink: (typeof drinkShortcuts)[0]) {
    carbs = drink.carbs;
    alcoholUnits = drink.alcoholUnits;
    alcoholType = drink.alcoholType;
    description = drink.label;
    // Clear food macros when selecting drink
    protein = undefined;
    fat = undefined;
  }

  function adjustAlcoholUnits(amount: number) {
    const current = alcoholUnits ?? 0;
    const newValue = Math.round((current + amount) * 10) / 10; // Round to 1 decimal
    if (newValue >= 0 && newValue <= 50) {
      alcoholUnits = newValue > 0 ? newValue : undefined;
    }
  }

  // Check if this is primarily an alcohol entry
  let isAlcoholEntry = $derived((alcoholUnits ?? 0) > 0);

  async function save() {
    // Allow saving if carbs > 0 OR alcohol units > 0
    if (carbs <= 0 && !isAlcoholEntry) return;

    saving = true;
    try {
      await eventsStore.logMeal(carbs, {
        protein,
        fat,
        description: description || undefined,
        alcoholUnits: alcoholUnits || undefined,
        alcoholType: alcoholType || undefined
      });
      goto('/');
    } catch {
      // Error is shown via store
    } finally {
      saving = false;
    }
  }

  // Use recent carbs if available, otherwise fall back to defaults
  const quickSelectValues = $derived(recentCarbs.length > 0 ? recentCarbs : defaultCarbQuickSelect);

  function applyPreset(preset: MealPreset) {
    carbs = preset.totalMacros.carbs;
    protein = preset.totalMacros.protein || undefined;
    fat = preset.totalMacros.fat || undefined;
    description = preset.name;
    // Clear alcohol when selecting preset
    alcoholUnits = undefined;
    alcoholType = undefined;
    // Mark preset as recently used
    presetsStore.markUsed(preset.id);
  }

  async function saveAsPreset() {
    if (!presetName.trim() || carbs <= 0) return;

    try {
      await presetsStore.create({
        name: presetName,
        items: [
          {
            name: description || presetName,
            macros: { carbs, protein: protein || 0, fat: fat || 0, calories: 0 }
          }
        ],
        totalMacros: { carbs, protein: protein || 0, fat: fat || 0, calories: 0 }
      });
      presetName = '';
      showSavePreset = false;
    } catch {
      // Error shown via store
    }
  }

  async function deletePreset(id: string) {
    await presetsStore.deletePreset(id);
  }
</script>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-6">
    <a href="/log" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
      <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back
    </a>
    <h1 class="text-2xl font-bold text-white">Log Meal</h1>
  </header>

  <div class="flex flex-1 flex-col">
    <!-- Camera Entry - Unified smart entry point -->
    <div class="mb-6">
      <a
        href="/log/meal/camera"
        class="flex w-full items-center gap-4 rounded-lg bg-gradient-to-r from-blue-500/10 via-purple-500/10 to-green-500/10 p-4 transition-all hover:from-blue-500/20 hover:via-purple-500/20 hover:to-green-500/20"
      >
        <div class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800">
          <svg class="h-7 w-7 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"
            />
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"
            />
          </svg>
        </div>
        <div class="flex-1">
          <span class="block font-medium text-white">Use Camera</span>
          <span class="text-sm text-gray-400">AI analysis, volume estimate, or label scan</span>
        </div>
        <svg class="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
        </svg>
      </a>
    </div>

    <!-- Saved Presets -->
    {#if presetsStore.presets.length > 0}
      <fieldset class="mb-4">
        <legend class="mb-2 block text-sm font-medium text-gray-400">Saved Meals</legend>
        <div class="flex flex-wrap gap-2">
          {#each presetsStore.presets as preset}
            <button
              type="button"
              class="group relative flex items-center gap-2 rounded-full bg-purple-500/10 px-3 py-2 text-sm transition-colors hover:bg-purple-500/20"
              onclick={() => applyPreset(preset)}
            >
              <span class="text-purple-300">{preset.name}</span>
              <span class="text-xs text-purple-400">{preset.totalMacros.carbs}g</span>
              <button
                type="button"
                class="ml-1 hidden text-purple-400 hover:text-red-400 group-hover:inline"
                onclick={(e) => {
                  e.stopPropagation();
                  deletePreset(preset.id);
                }}
                aria-label={`Delete ${preset.name}`}
              >
                &times;
              </button>
            </button>
          {/each}
        </div>
      </fieldset>
    {/if}

    <!-- Divider -->
    <div class="mb-6 flex items-center gap-3">
      <div class="h-px flex-1 bg-gray-800"></div>
      <span class="text-xs text-gray-500">or enter manually</span>
      <div class="h-px flex-1 bg-gray-800"></div>
    </div>

    <!-- Food Shortcuts -->
    <fieldset class="mb-4">
      <legend class="mb-2 block text-sm font-medium text-gray-400">Quick add - Food</legend>
      <div class="flex flex-wrap gap-2">
        {#each foodShortcuts as food}
          <button
            type="button"
            class="flex items-center gap-1 rounded-full bg-gray-800 px-3 py-2 text-sm transition-colors hover:bg-gray-700"
            onclick={() => applyFoodShortcut(food)}
            aria-label={`Add ${food.label} (${food.carbs}g carbs)`}
          >
            <span class="text-lg">{food.icon}</span>
            <span class="text-gray-300">{food.carbs}g</span>
          </button>
        {/each}
      </div>
    </fieldset>

    <!-- Drink Shortcuts -->
    <fieldset class="mb-6">
      <legend class="mb-2 block text-sm font-medium text-gray-400">Quick add - Drinks</legend>
      <div class="flex flex-wrap gap-2">
        {#each drinkShortcuts as drink}
          <button
            type="button"
            class="flex items-center gap-1 rounded-full bg-amber-500/10 px-3 py-2 text-sm transition-colors hover:bg-amber-500/20"
            onclick={() => applyDrinkShortcut(drink)}
            aria-label={`Add ${drink.label} (${drink.carbs}g carbs, ${drink.alcoholUnits} units)`}
          >
            <span class="text-lg">{drink.icon}</span>
            <span class="text-amber-300">{drink.alcoholUnits}u</span>
          </button>
        {/each}
      </div>
    </fieldset>

    <!-- Carbs Input with +/-1 and +/-5 adjustments -->
    <div class="mb-6">
      <label for="carbs-input" class="mb-2 block text-sm font-medium text-gray-400">
        Carbohydrates (g) <span class="text-red-400">*</span>
      </label>
      <div class="flex items-center justify-center gap-3">
        <!-- -5 button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustCarbs(-5)}
          disabled={carbs < 5}
          aria-label="Decrease carbs by 5"
        >
          -5
        </button>
        <!-- -1 button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustCarbs(-1)}
          disabled={carbs <= 0}
          aria-label="Decrease carbs by 1"
        >
          -
        </button>
        <!-- Value display -->
        <div class="w-24 text-center">
          <input
            id="carbs-input"
            type="number"
            bind:value={carbs}
            min="0"
            max="500"
            class="w-full bg-transparent text-center text-5xl font-bold text-white focus:outline-none"
            aria-describedby="carbs-label"
          />
          <span id="carbs-label" class="text-sm text-gray-400">grams</span>
        </div>
        <!-- +1 button -->
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustCarbs(1)}
          disabled={carbs >= 500}
          aria-label="Increase carbs by 1"
        >
          +
        </button>
        <!-- +5 button -->
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustCarbs(5)}
          disabled={carbs > 495}
          aria-label="Increase carbs by 5"
        >
          +5
        </button>
      </div>
    </div>

    <!-- Quick Select (recent carbs or defaults) -->
    <fieldset class="mb-6">
      <legend class="mb-2 block text-sm font-medium text-gray-400">
        {recentCarbs.length > 0 ? 'Recent values' : 'Quick select'}
        {#if loadingRecent}
          <span class="ml-2 text-xs text-gray-500">Loading...</span>
        {/if}
      </legend>
      <div class="flex flex-wrap gap-2">
        {#each quickSelectValues as value}
          <button
            type="button"
            class="rounded-full px-4 py-2 text-sm font-medium transition-colors {carbs === value
              ? 'bg-green-500 text-white'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (carbs = value)}
          >
            {value}g
          </button>
        {/each}
      </div>
    </fieldset>

    <!-- Alcohol Logging Section -->
    <details class="mb-6" open={isAlcoholEntry}>
      <summary class="cursor-pointer text-sm font-medium text-amber-400 hover:text-amber-300">
        Alcohol ({alcoholUnits ?? 0} units)
      </summary>
      <div class="mt-3 rounded-lg bg-amber-500/5 p-4">
        <!-- Alcohol Units Input -->
        <div class="mb-4">
          <label for="alcohol-units" class="mb-2 block text-xs font-medium text-gray-400">
            Standard drink units
          </label>
          <div class="flex items-center justify-center gap-3">
            <button
              type="button"
              class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-800 text-lg text-amber-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
              onclick={() => adjustAlcoholUnits(-0.5)}
              disabled={(alcoholUnits ?? 0) < 0.5}
              aria-label="Decrease alcohol by 0.5 units"
            >
              -
            </button>
            <div class="w-20 text-center">
              <input
                id="alcohol-units"
                type="number"
                bind:value={alcoholUnits}
                min="0"
                max="50"
                step="0.1"
                placeholder="0"
                class="w-full bg-transparent text-center text-3xl font-bold text-amber-300 placeholder-gray-600 focus:outline-none"
              />
              <span class="text-xs text-gray-400">units</span>
            </div>
            <button
              type="button"
              class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-800 text-lg text-amber-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
              onclick={() => adjustAlcoholUnits(0.5)}
              disabled={(alcoholUnits ?? 0) >= 50}
              aria-label="Increase alcohol by 0.5 units"
            >
              +
            </button>
          </div>
        </div>

        <!-- Alcohol Type Selector -->
        <div>
          <label for="alcohol-type" class="mb-2 block text-xs font-medium text-gray-400">
            Drink type
          </label>
          <select
            id="alcohol-type"
            bind:value={alcoholType}
            class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-white focus:border-amber-500 focus:outline-none focus:ring-1 focus:ring-amber-500"
          >
            {#each alcoholTypeOptions as option}
              <option value={option.value || undefined}>{option.label}</option>
            {/each}
          </select>
        </div>
      </div>
    </details>

    <!-- Optional Macros (collapsible) -->
    <details class="mb-6">
      <summary class="cursor-pointer text-sm font-medium text-gray-400 hover:text-gray-300">
        Additional macros (optional)
      </summary>
      <div class="mt-3 grid grid-cols-2 gap-3">
        <div>
          <label for="protein" class="mb-1 block text-xs font-medium text-gray-500"
            >Protein (g)</label
          >
          <input
            id="protein"
            type="number"
            bind:value={protein}
            min="0"
            placeholder="-"
            class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
          />
        </div>
        <div>
          <label for="fat" class="mb-1 block text-xs font-medium text-gray-500">Fat (g)</label>
          <input
            id="fat"
            type="number"
            bind:value={fat}
            min="0"
            placeholder="-"
            class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
          />
        </div>
      </div>
    </details>

    <!-- Description -->
    <div class="mb-6 flex-1">
      <label for="description" class="mb-2 block text-sm font-medium text-gray-400">
        Description (optional)
      </label>
      <textarea
        id="description"
        bind:value={description}
        rows="2"
        placeholder="What did you eat?"
        class="w-full resize-none rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      ></textarea>
    </div>

    <!-- Save as Preset Option -->
    {#if carbs > 0 && !isAlcoholEntry}
      <div class="mb-4">
        {#if showSavePreset}
          <div class="flex items-center gap-2 rounded-lg bg-purple-500/10 p-3">
            <input
              type="text"
              bind:value={presetName}
              placeholder="Preset name"
              class="flex-1 rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white placeholder-gray-500 focus:border-purple-500 focus:outline-none focus:ring-1 focus:ring-purple-500"
              onkeydown={(e) => e.key === 'Enter' && saveAsPreset()}
            />
            <button
              type="button"
              class="rounded-lg bg-purple-500 px-3 py-2 text-sm font-medium text-white transition-colors hover:bg-purple-600 disabled:opacity-50"
              onclick={saveAsPreset}
              disabled={!presetName.trim()}
            >
              Save
            </button>
            <button
              type="button"
              class="rounded-lg px-3 py-2 text-sm text-gray-400 transition-colors hover:text-gray-200"
              onclick={() => {
                showSavePreset = false;
                presetName = '';
              }}
            >
              Cancel
            </button>
          </div>
        {:else}
          <button
            type="button"
            class="flex w-full items-center justify-center gap-2 rounded-lg border border-dashed border-gray-700 px-3 py-2 text-sm text-gray-400 transition-colors hover:border-purple-500 hover:text-purple-400"
            onclick={() => {
              showSavePreset = true;
              presetName = description || '';
            }}
          >
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z" />
            </svg>
            Save as preset
          </button>
        {/if}
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
      disabled={carbs <= 0 && !isAlcoholEntry}
      loading={saving}
    >
      {#if isAlcoholEntry && carbs <= 0}
        Log {alcoholUnits} units alcohol
      {:else if isAlcoholEntry}
        Log {carbs}g carbs + {alcoholUnits}u alcohol
      {:else}
        Log {carbs}g carbs
      {/if}
    </Button>
  </div>
</div>
