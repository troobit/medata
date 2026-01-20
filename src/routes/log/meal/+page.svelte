<script lang="ts">
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { Button } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';

  let carbs = $state(0);
  let protein = $state<number | undefined>(undefined);
  let fat = $state<number | undefined>(undefined);
  let description = $state('');
  let photoUrl = $state<string | undefined>(undefined);
  let saving = $state(false);
  let recentCarbs = $state<number[]>([]);
  let loadingRecent = $state(true);

  // Default quick-select values as fallback when no recent carbs exist
  const defaultCarbQuickSelect = [15, 30, 45, 60, 75, 90];

  // Food icon shortcuts with default carb values
  const foodShortcuts = [
    { icon: '🍞', label: 'Bread', carbs: 15 },
    { icon: '🍕', label: 'Pizza', carbs: 30, fat: 12 },
    { icon: '🍔', label: 'Burger', carbs: 35, protein: 25, fat: 20 },
    { icon: '🍺', label: 'Beer', carbs: 12 },
    { icon: '🍎', label: 'Apple', carbs: 25 },
    { icon: '🍚', label: 'Rice', carbs: 45 }
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
  }

  async function handlePhotoCapture() {
    // Create a file input for photo selection
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.capture = 'environment'; // Use back camera on mobile

    input.onchange = async (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (file) {
        // Convert to base64 data URL for storage
        const reader = new FileReader();
        reader.onload = () => {
          photoUrl = reader.result as string;
        };
        reader.readAsDataURL(file);
      }
    };

    input.click();
  }

  function removePhoto() {
    photoUrl = undefined;
  }

  async function save() {
    if (carbs <= 0) return;

    saving = true;
    try {
      await eventsStore.logMeal(carbs, {
        protein,
        fat,
        description: description || undefined,
        photoUrl
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
    <!-- Smart Entry Options -->
    <div class="mb-6">
      <span class="mb-2 block text-sm font-medium text-gray-400">Smart Entry</span>
      <div class="grid grid-cols-3 gap-2">
        <a
          href="/log/meal/photo"
          class="flex flex-col items-center rounded-lg bg-blue-500/10 p-3 text-center transition-colors hover:bg-blue-500/20"
        >
          <span class="mb-1 text-2xl">📷</span>
          <span class="text-xs text-blue-400">AI Photo</span>
        </a>
        <a
          href="/log/meal/estimate"
          class="flex flex-col items-center rounded-lg bg-purple-500/10 p-3 text-center transition-colors hover:bg-purple-500/20"
        >
          <span class="mb-1 text-2xl">📐</span>
          <span class="text-xs text-purple-400">Estimate</span>
        </a>
        <a
          href="/log/meal/label"
          class="flex flex-col items-center rounded-lg bg-green-500/10 p-3 text-center transition-colors hover:bg-green-500/20"
        >
          <span class="mb-1 text-2xl">🏷️</span>
          <span class="text-xs text-green-400">Scan Label</span>
        </a>
      </div>
    </div>

    <!-- Divider -->
    <div class="mb-6 flex items-center gap-3">
      <div class="h-px flex-1 bg-gray-800"></div>
      <span class="text-xs text-gray-500">or enter manually</span>
      <div class="h-px flex-1 bg-gray-800"></div>
    </div>

    <!-- Photo Capture -->
    <div class="mb-6">
      {#if photoUrl}
        <div class="relative">
          <img src={photoUrl} alt="Food being logged" class="h-32 w-full rounded-lg object-cover" />
          <button
            type="button"
            class="absolute right-2 top-2 rounded-full bg-gray-900/80 p-1 text-gray-300 hover:bg-gray-900"
            onclick={removePhoto}
            aria-label="Remove photo"
          >
            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>
      {:else}
        <button
          type="button"
          class="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed border-gray-700 bg-gray-800/50 px-4 py-4 text-gray-400 transition-colors hover:border-gray-600 hover:bg-gray-800 hover:text-gray-300"
          onclick={handlePhotoCapture}
        >
          <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
          <span>Add photo</span>
        </button>
      {/if}
    </div>

    <!-- Food Shortcuts -->
    <fieldset class="mb-6">
      <legend class="mb-2 block text-sm font-medium text-gray-400">Quick add</legend>
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
      disabled={carbs <= 0}
      loading={saving}
    >
      Log {carbs}g carbs
    </Button>
  </div>
</div>
