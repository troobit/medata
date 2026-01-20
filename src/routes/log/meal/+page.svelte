<script lang="ts">
  import { goto } from '$app/navigation';
  import { Button } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';

  interface FoodPreset {
    icon: string;
    name: string;
    carbs: number;
    calories?: number;
    protein?: number;
    fat?: number;
  }

  const defaultPresets: FoodPreset[] = [
    { icon: '🍔', name: 'Burger', carbs: 45, calories: 550, protein: 25, fat: 30 },
    { icon: '🍕', name: 'Pizza', carbs: 35, calories: 300, protein: 12, fat: 12 },
    { icon: '🍺', name: 'Pint', carbs: 15, calories: 180 },
    { icon: '🍞', name: 'Bread', carbs: 15, calories: 80, protein: 3 },
    { icon: '🍎', name: 'Apple', carbs: 25, calories: 95, fat: 0 },
    { icon: '🍚', name: 'Rice', carbs: 45, calories: 200, protein: 4 }
  ];

  let carbs = $state(0);
  let calories = $state<number | undefined>(undefined);
  let protein = $state<number | undefined>(undefined);
  let fat = $state<number | undefined>(undefined);
  let description = $state('');
  let saving = $state(false);
  let showMoreOptions = $state(false);
  let photoUrl = $state<string | undefined>(undefined);
  let fileInput = $state<HTMLInputElement | null>(null);

  function increment() {
    if (carbs < 500) carbs++;
  }

  function decrement() {
    if (carbs > 0) carbs--;
  }

  function adjustBy(amount: number) {
    const newValue = carbs + amount;
    if (newValue >= 0 && newValue <= 500) {
      carbs = newValue;
    }
  }

  function applyPreset(preset: FoodPreset) {
    carbs = preset.carbs;
    if (preset.calories) calories = preset.calories;
    if (preset.protein) protein = preset.protein;
    if (preset.fat) fat = preset.fat;
    description = preset.name;
  }

  function handlePhotoCapture(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (e) => {
        photoUrl = e.target?.result as string;
      };
      reader.readAsDataURL(file);
    }
  }

  function removePhoto() {
    photoUrl = undefined;
    if (fileInput) {
      fileInput.value = '';
    }
  }

  async function save() {
    if (carbs <= 0) return;

    saving = true;
    try {
      await eventsStore.logMeal(carbs, {
        calories,
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
</script>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-8">
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
      <span class="mb-2 block text-sm font-medium text-gray-400">Photo (optional)</span>
      {#if photoUrl}
        <div class="relative">
          <img
            src={photoUrl}
            alt="Captured food"
            class="h-32 w-full rounded-lg object-cover"
          />
          <button
            type="button"
            aria-label="Remove photo"
            class="absolute right-2 top-2 rounded-full bg-gray-900/80 p-1.5 text-gray-300 hover:bg-gray-900 hover:text-white"
            onclick={removePhoto}
          >
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      {:else}
        <label class="flex h-24 cursor-pointer items-center justify-center rounded-lg border-2 border-dashed border-gray-700 bg-gray-800/50 transition-colors hover:border-gray-600 hover:bg-gray-800">
          <div class="flex flex-col items-center text-gray-400">
            <svg class="mb-1 h-8 w-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
            <span class="text-sm">Take or choose photo</span>
          </div>
          <input
            type="file"
            accept="image/*"
            capture="environment"
            class="hidden"
            bind:this={fileInput}
            onchange={handlePhotoCapture}
          />
        </label>
      {/if}
    </div>

    <!-- Food Presets -->
    <div class="mb-6">
      <span class="mb-2 block text-sm font-medium text-gray-400">Quick add</span>
      <div class="grid grid-cols-3 gap-2">
        {#each defaultPresets as preset (preset.name)}
          <button
            type="button"
            class="flex flex-col items-center rounded-lg bg-gray-800 px-3 py-3 transition-colors hover:bg-gray-700 active:bg-gray-600"
            onclick={() => applyPreset(preset)}
          >
            <span class="text-2xl">{preset.icon}</span>
            <span class="mt-1 text-xs text-gray-400">{preset.name}</span>
            <span class="text-xs text-gray-500">{preset.carbs}g</span>
          </button>
        {/each}
      </div>
    </div>

    <!-- Carbs Input -->
    <div class="mb-6 flex-1">
      <span class="mb-2 block text-sm font-medium text-gray-400">Carbohydrates (g)</span>
      <div class="flex items-center justify-center gap-6">
        <button
          type="button"
          class="flex h-16 w-16 items-center justify-center rounded-full bg-gray-800 text-3xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={decrement}
          disabled={carbs <= 0}
        >
          -
        </button>
        <div class="w-24 text-center">
          <input
            type="number"
            bind:value={carbs}
            min="0"
            max="500"
            aria-label="Carbohydrates in grams"
            class="w-full bg-transparent text-center text-5xl font-bold text-white focus:outline-none"
          />
          <span class="text-sm text-gray-400">grams</span>
        </div>
        <button
          type="button"
          class="flex h-16 w-16 items-center justify-center rounded-full bg-gray-800 text-3xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={increment}
          disabled={carbs >= 500}
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
          disabled={carbs < 5}
        >
          -5
        </button>
        <button
          type="button"
          class="rounded-lg bg-gray-800 px-6 py-3 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600"
          onclick={() => adjustBy(5)}
          disabled={carbs >= 495}
        >
          +5
        </button>
      </div>
    </div>

    <!-- Quick Carb Select -->
    <div class="mb-6">
      <span class="mb-2 block text-sm font-medium text-gray-400">Quick select</span>
      <div class="flex flex-wrap gap-2">
        {#each [15, 30, 45, 60, 75, 90] as value (value)}
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
    </div>

    <!-- More Options Toggle -->
    <button
      type="button"
      class="mb-4 flex w-full items-center justify-between rounded-lg bg-gray-800/50 px-4 py-3 text-sm text-gray-400 transition-colors hover:bg-gray-800"
      onclick={() => (showMoreOptions = !showMoreOptions)}
    >
      <span>More options</span>
      <svg
        class="h-5 w-5 transform transition-transform {showMoreOptions ? 'rotate-180' : ''}"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </button>

    {#if showMoreOptions}
      <!-- Optional Macros -->
      <div class="mb-4 grid grid-cols-3 gap-3">
        <div>
          <label for="calories" class="mb-2 block text-xs font-medium text-gray-400">Calories</label>
          <input
            id="calories"
            type="number"
            bind:value={calories}
            min="0"
            placeholder="-"
            class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
          />
        </div>
        <div>
          <label for="protein" class="mb-2 block text-xs font-medium text-gray-400">Protein (g)</label>
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
          <label for="fat" class="mb-2 block text-xs font-medium text-gray-400">Fat (g)</label>
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

      <!-- Description -->
      <div class="mb-4">
        <label for="description" class="mb-2 block text-sm font-medium text-gray-400">
          Description
        </label>
        <textarea
          id="description"
          bind:value={description}
          rows="2"
          placeholder="What did you eat?"
          class="w-full resize-none rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
        ></textarea>
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
      disabled={carbs <= 0}
      loading={saving}
    >
      Log Meal
    </Button>
  </div>
</div>
