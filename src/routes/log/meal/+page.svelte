<script lang="ts">
  import { goto } from '$app/navigation';
  import { Button } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';
  import type { AlcoholType } from '$lib/types';

  // Preset type for quick meal shortcuts
  interface MealPreset {
    icon: string;
    label: string;
    carbs: number;
    calories?: number;
    protein?: number;
    fat?: number;
    alcoholUnits?: number;
    alcoholType?: AlcoholType;
  }

  // Default meal presets (customizable in settings in future)
  const mealPresets: MealPreset[] = [
    { icon: '🍔', label: 'Burger', carbs: 45, protein: 25, fat: 30 },
    { icon: '🍕', label: 'Pizza', carbs: 35, protein: 12, fat: 12 },
    { icon: '🍞', label: 'Toast', carbs: 15, protein: 3, fat: 1 },
    { icon: '🍎', label: 'Apple', carbs: 25, protein: 0, fat: 0 },
    { icon: '🥗', label: 'Salad', carbs: 10, protein: 5, fat: 8 },
    { icon: '🍚', label: 'Rice', carbs: 45, protein: 4, fat: 0 }
  ];

  // Drink presets for quick alcohol logging
  const drinkPresets: MealPreset[] = [
    { icon: '🍺', label: 'Pint', carbs: 15, alcoholUnits: 2, alcoholType: 'beer' },
    { icon: '🍷', label: 'Wine', carbs: 4, alcoholUnits: 2, alcoholType: 'wine' },
    { icon: '🥃', label: 'Spirit', carbs: 0, alcoholUnits: 1, alcoholType: 'spirit' },
    { icon: '🍹', label: 'Cocktail', carbs: 20, alcoholUnits: 2, alcoholType: 'mixed' }
  ];

  let carbs = $state(0);
  let protein = $state(0);
  let fat = $state(0);
  let alcoholUnits = $state(0);
  let alcoholType = $state<AlcoholType | ''>('');
  let description = $state('');
  let saving = $state(false);
  let showDetails = $state(false);
  let photoPreview = $state<string | null>(null);

  function incrementCarbs(amount: number = 1) {
    carbs = Math.min(500, Math.max(0, carbs + amount));
  }

  function decrementCarbs(amount: number = 1) {
    carbs = Math.max(0, carbs - amount);
  }

  function incrementProtein(amount: number = 1) {
    protein = Math.min(200, Math.max(0, protein + amount));
  }

  function decrementProtein(amount: number = 1) {
    protein = Math.max(0, protein - amount);
  }

  function incrementFat(amount: number = 1) {
    fat = Math.min(200, Math.max(0, fat + amount));
  }

  function decrementFat(amount: number = 1) {
    fat = Math.max(0, fat - amount);
  }

  function incrementAlcohol(amount: number = 1) {
    alcoholUnits = Math.min(20, Math.max(0, alcoholUnits + amount));
  }

  function decrementAlcohol(amount: number = 1) {
    alcoholUnits = Math.max(0, alcoholUnits - amount);
  }

  function applyPreset(preset: MealPreset) {
    carbs = preset.carbs;
    protein = preset.protein ?? 0;
    fat = preset.fat ?? 0;
    alcoholUnits = preset.alcoholUnits ?? 0;
    alcoholType = preset.alcoholType ?? '';
    description = preset.label;
  }

  function handlePhotoSelect(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (e) => {
        photoPreview = e.target?.result as string;
      };
      reader.readAsDataURL(file);
    }
  }

  function clearPhoto() {
    photoPreview = null;
  }

  // Allow saving if there's carbs OR alcohol
  const canSave = $derived(carbs > 0 || alcoholUnits > 0);

  async function save() {
    if (!canSave) return;

    saving = true;
    try {
      // TODO: Upload photo and get URL when AI integration is complete
      await eventsStore.logMeal(carbs, {
        protein: protein > 0 ? protein : undefined,
        fat: fat > 0 ? fat : undefined,
        alcoholUnits: alcoholUnits > 0 ? alcoholUnits : undefined,
        alcoholType: alcoholUnits > 0 && alcoholType ? alcoholType : undefined,
        description: description || undefined
      });
      goto('/');
    } catch {
      // Error is shown via store
    } finally {
      saving = false;
    }
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
    <!-- Photo Capture -->
    <div class="mb-6">
      {#if photoPreview}
        <div class="relative">
          <img src={photoPreview} alt="Captured meal" class="h-40 w-full rounded-lg object-cover" />
          <button
            type="button"
            class="absolute right-2 top-2 flex h-8 w-8 items-center justify-center rounded-full bg-gray-900/80 text-white hover:bg-gray-900"
            onclick={clearPhoto}
            aria-label="Remove photo"
          >
            ✕
          </button>
        </div>
      {:else}
        <label
          class="flex h-24 cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed border-gray-700 bg-gray-800/50 text-gray-400 transition-colors hover:border-gray-600 hover:bg-gray-800"
        >
          <svg class="mb-1 h-8 w-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
          <span class="text-sm">Add photo</span>
          <input
            type="file"
            accept="image/*"
            capture="environment"
            class="hidden"
            onchange={handlePhotoSelect}
          />
        </label>
      {/if}
    </div>

    <!-- Quick Presets - Food and Drinks together -->
    <div class="mb-6">
      <span id="food-shortcuts-label" class="mb-2 block text-sm font-medium text-gray-400">
        Food
      </span>
      <div class="mb-4 grid grid-cols-6 gap-2" role="group" aria-labelledby="food-shortcuts-label">
        {#each mealPresets as preset (preset.label)}
          <button
            type="button"
            class="flex flex-col items-center rounded-lg p-2 text-center transition-colors {description ===
            preset.label
              ? 'bg-green-500/20 ring-2 ring-green-500'
              : 'bg-gray-800 hover:bg-gray-700'}"
            onclick={() => applyPreset(preset)}
            title="{preset.label}: {preset.carbs}g carbs"
          >
            <span class="text-2xl">{preset.icon}</span>
            <span class="mt-1 text-[10px] text-gray-400">{preset.carbs}g</span>
          </button>
        {/each}
      </div>

      <span id="drink-shortcuts-label" class="mb-2 block text-sm font-medium text-gray-400">
        Drinks
      </span>
      <div class="grid grid-cols-4 gap-2" role="group" aria-labelledby="drink-shortcuts-label">
        {#each drinkPresets as preset (preset.label)}
          <button
            type="button"
            class="flex flex-col items-center rounded-lg p-2 text-center transition-colors {description ===
            preset.label
              ? 'bg-purple-500/20 ring-2 ring-purple-500'
              : 'bg-gray-800 hover:bg-gray-700'}"
            onclick={() => applyPreset(preset)}
            title="{preset.label}: {preset.carbs}g carbs, {preset.alcoholUnits}u alcohol"
          >
            <span class="text-2xl">{preset.icon}</span>
            <span class="mt-1 text-[10px] text-gray-400">{preset.carbs}g / {preset.alcoholUnits}u</span>
          </button>
        {/each}
      </div>
    </div>

    <!-- Primary Inputs: Carbs and Alcohol side by side -->
    <div class="mb-6 grid grid-cols-2 gap-4">
      <!-- Carbs Stepper -->
      <div class="rounded-lg bg-gray-800/50 p-4">
        <label for="carbs-input" class="mb-2 block text-center text-sm font-medium text-green-400">
          Carbs (g)
        </label>
        <div class="flex items-center justify-center gap-2">
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
            onclick={() => decrementCarbs(5)}
            disabled={carbs < 5}
            aria-label="Decrease by 5g"
          >
            -5
          </button>
          <div class="w-16 text-center">
            <input
              id="carbs-input"
              type="number"
              bind:value={carbs}
              min="0"
              max="500"
              class="w-full bg-transparent text-center text-3xl font-bold text-white focus:outline-none"
            />
          </div>
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
            onclick={() => incrementCarbs(5)}
            disabled={carbs > 495}
            aria-label="Increase by 5g"
          >
            +5
          </button>
        </div>
      </div>

      <!-- Alcohol Stepper -->
      <div class="rounded-lg bg-gray-800/50 p-4">
        <label for="alcohol-input" class="mb-2 block text-center text-sm font-medium text-purple-400">
          Drinks
        </label>
        <div class="flex items-center justify-center gap-2">
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
            onclick={() => decrementAlcohol(1)}
            disabled={alcoholUnits <= 0}
            aria-label="Decrease by 1"
          >
            -
          </button>
          <div class="w-16 text-center">
            <input
              id="alcohol-input"
              type="number"
              bind:value={alcoholUnits}
              min="0"
              max="20"
              step="0.5"
              class="w-full bg-transparent text-center text-3xl font-bold text-white focus:outline-none"
            />
          </div>
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
            onclick={() => incrementAlcohol(1)}
            disabled={alcoholUnits >= 20}
            aria-label="Increase by 1"
          >
            +
          </button>
        </div>
      </div>
    </div>

    <!-- Expandable Details Section -->
    <div class="mb-6">
      <button
        type="button"
        class="flex w-full items-center justify-between rounded-lg bg-gray-800 px-4 py-3 text-left text-gray-400 transition-colors hover:bg-gray-700"
        onclick={() => (showDetails = !showDetails)}
        aria-expanded={showDetails}
      >
        <span class="text-sm font-medium">More details</span>
        <svg
          class="h-5 w-5 transition-transform {showDetails ? 'rotate-180' : ''}"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </button>

      {#if showDetails}
        <div class="mt-3 space-y-4 rounded-lg bg-gray-800/50 p-4">
          <!-- Protein Stepper -->
          <div>
            <label for="protein-input" class="mb-2 block text-xs font-medium text-gray-400">
              Protein (g)
            </label>
            <div class="flex items-center justify-center gap-2">
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-lg text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => decrementProtein(5)}
                disabled={protein < 5}
                aria-label="Decrease protein by 5g"
              >
                -5
              </button>
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => decrementProtein(1)}
                disabled={protein <= 0}
                aria-label="Decrease protein by 1g"
              >
                -
              </button>
              <div class="w-16 text-center">
                <input
                  id="protein-input"
                  type="number"
                  bind:value={protein}
                  min="0"
                  max="200"
                  class="w-full bg-transparent text-center text-2xl font-bold text-white focus:outline-none"
                />
              </div>
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => incrementProtein(1)}
                disabled={protein >= 200}
                aria-label="Increase protein by 1g"
              >
                +
              </button>
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-lg text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => incrementProtein(5)}
                disabled={protein > 195}
                aria-label="Increase protein by 5g"
              >
                +5
              </button>
            </div>
          </div>

          <!-- Fat Stepper -->
          <div>
            <label for="fat-input" class="mb-2 block text-xs font-medium text-gray-400">
              Fat (g)
            </label>
            <div class="flex items-center justify-center gap-2">
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-lg text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => decrementFat(5)}
                disabled={fat < 5}
                aria-label="Decrease fat by 5g"
              >
                -5
              </button>
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => decrementFat(1)}
                disabled={fat <= 0}
                aria-label="Decrease fat by 1g"
              >
                -
              </button>
              <div class="w-16 text-center">
                <input
                  id="fat-input"
                  type="number"
                  bind:value={fat}
                  min="0"
                  max="200"
                  class="w-full bg-transparent text-center text-2xl font-bold text-white focus:outline-none"
                />
              </div>
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => incrementFat(1)}
                disabled={fat >= 200}
                aria-label="Increase fat by 1g"
              >
                +
              </button>
              <button
                type="button"
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-lg text-gray-300 transition-colors hover:bg-gray-600 active:bg-gray-500 disabled:opacity-50"
                onclick={() => incrementFat(5)}
                disabled={fat > 195}
                aria-label="Increase fat by 5g"
              >
                +5
              </button>
            </div>
          </div>

          <!-- Drink Type (only show if alcohol) -->
          {#if alcoholUnits > 0}
            <div>
              <label for="alcohol-type" class="mb-1 block text-xs font-medium text-gray-400">
                Drink type
              </label>
              <select
                id="alcohol-type"
                bind:value={alcoholType}
                class="w-full rounded-lg border border-gray-700 bg-gray-900 px-3 py-2 text-white focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
              >
                <option value="">Not specified</option>
                <option value="beer">Beer / Cider</option>
                <option value="wine">Wine</option>
                <option value="spirit">Spirits / Shots</option>
                <option value="mixed">Cocktails / Mixed</option>
              </select>
            </div>
          {/if}

          <!-- Description -->
          <div>
            <label for="description" class="mb-1 block text-xs font-medium text-gray-400">
              Description
            </label>
            <textarea
              id="description"
              bind:value={description}
              rows="2"
              placeholder="What did you eat or drink?"
              class="w-full resize-none rounded-lg border border-gray-700 bg-gray-900 px-3 py-2 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
            ></textarea>
          </div>
        </div>
      {/if}
    </div>

    <!-- Error Display -->
    {#if eventsStore.error}
      <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
        {eventsStore.error}
      </div>
    {/if}

    <!-- Save Button -->
    <div class="mt-auto">
      <Button
        variant="primary"
        size="lg"
        class="w-full"
        onclick={save}
        disabled={!canSave}
        loading={saving}
      >
        {#if alcoholUnits > 0 && carbs > 0}
          Log {carbs}g carbs + {alcoholUnits} drinks
        {:else if alcoholUnits > 0}
          Log {alcoholUnits} drinks
        {:else}
          Log {carbs}g carbs
        {/if}
      </Button>
    </div>
  </div>
</div>
