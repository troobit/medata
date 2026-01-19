<script lang="ts">
  import { goto } from '$app/navigation';
  import { Button } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';

  let carbs = $state(0);
  let calories = $state<number | undefined>(undefined);
  let protein = $state<number | undefined>(undefined);
  let fat = $state<number | undefined>(undefined);
  let description = $state('');
  let saving = $state(false);

  async function save() {
    if (carbs <= 0) return;

    saving = true;
    try {
      await eventsStore.logMeal(carbs, {
        calories,
        protein,
        fat,
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
    <!-- Carbs Input (Required) -->
    <div class="mb-6">
      <label for="carbs" class="mb-2 block text-sm font-medium text-gray-400">
        Carbohydrates (g) <span class="text-red-400">*</span>
      </label>
      <input
        id="carbs"
        type="number"
        bind:value={carbs}
        min="0"
        max="500"
        placeholder="0"
        class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-lg text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      />
    </div>

    <!-- Optional Macros -->
    <div class="mb-6 grid grid-cols-3 gap-3">
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
        <label for="protein" class="mb-2 block text-xs font-medium text-gray-400">Protein (g)</label
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
    <div class="mb-6 flex-1">
      <label for="description" class="mb-2 block text-sm font-medium text-gray-400">
        Description (optional)
      </label>
      <textarea
        id="description"
        bind:value={description}
        rows="3"
        placeholder="What did you eat?"
        class="w-full resize-none rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white placeholder-gray-500 focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      ></textarea>
    </div>

    <!-- Quick Carb Select -->
    <div class="mb-8">
      <label class="mb-2 block text-sm font-medium text-gray-400">Quick select</label>
      <div class="flex flex-wrap gap-2">
        {#each [15, 30, 45, 60, 75, 90] as value}
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
