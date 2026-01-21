<script lang="ts">
  /**
   * FoodTypeSelector - Search and select food type from database.
   * Shows categories and search results for macro estimation.
   */
  import type { FoodDensityEntry } from '$lib/types/local-estimation';
  import { foodDensityLookup } from '$lib/services/local-estimation';

  interface Props {
    selected?: FoodDensityEntry | null;
    onSelect?: (food: FoodDensityEntry) => void;
  }

  let { selected = null, onSelect }: Props = $props();

  let searchQuery = $state('');
  let searchResults = $state<FoodDensityEntry[]>([]);
  let showCategories = $state(true);
  let selectedCategory = $state<string | null>(null);

  const categories = foodDensityLookup.getCategories();
  const popularFoods = foodDensityLookup.getPopular(8);

  // Category icons
  const categoryIcons: Record<string, string> = {
    grains: '🍚',
    proteins: '🍗',
    vegetables: '🥦',
    fruits: '🍎',
    dairy: '🧀',
    mixed: '🍲',
    snacks: '🍪',
    sauces: '🥫'
  };

  // Search when query changes
  $effect(() => {
    if (searchQuery.trim().length >= 2) {
      searchResults = foodDensityLookup.search(searchQuery, 15);
      showCategories = false;
    } else {
      searchResults = [];
      showCategories = true;
      selectedCategory = null;
    }
  });

  function selectFood(food: FoodDensityEntry) {
    onSelect?.(food);
  }

  function selectCategory(category: string) {
    selectedCategory = category;
    showCategories = false;
    searchQuery = '';
  }

  function goBack() {
    if (selectedCategory) {
      selectedCategory = null;
      showCategories = true;
    }
  }

  function clearSearch() {
    searchQuery = '';
    searchResults = [];
    showCategories = true;
    selectedCategory = null;
  }

  // Get foods for selected category
  const categoryFoods = $derived(
    selectedCategory ? foodDensityLookup.getByCategory(selectedCategory) : []
  );
</script>

<div class="flex flex-col">
  <!-- Search bar -->
  <div class="relative mb-4">
    <input
      type="text"
      bind:value={searchQuery}
      placeholder="Search foods..."
      class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 pl-10 text-white placeholder-gray-500 focus:border-purple-500 focus:outline-none focus:ring-1 focus:ring-purple-500"
    />
    <svg
      class="absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-500"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
      />
    </svg>
    {#if searchQuery}
      <button
        type="button"
        class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-white"
        onclick={clearSearch}
        aria-label="Clear search"
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
    {/if}
  </div>

  <!-- Selected food indicator -->
  {#if selected}
    <div class="mb-4 flex items-center justify-between rounded-lg bg-purple-500/20 px-4 py-3">
      <div>
        <p class="font-medium text-white">{selected.name}</p>
        <p class="text-sm text-purple-300">{selected.category}</p>
      </div>
      <span class="text-2xl">{categoryIcons[selected.category] || '🍽️'}</span>
    </div>
  {/if}

  <!-- Content area -->
  <div class="min-h-64 overflow-y-auto">
    {#if searchResults.length > 0}
      <!-- Search results -->
      <div class="space-y-1">
        {#each searchResults as food (food.id)}
          <button
            type="button"
            class="flex w-full items-center justify-between rounded-lg px-4 py-3 text-left transition-colors {selected?.id ===
            food.id
              ? 'bg-purple-500/30'
              : 'hover:bg-gray-800'}"
            onclick={() => selectFood(food)}
          >
            <div>
              <p class="text-white">{food.name}</p>
              <p class="text-xs text-gray-400">
                {food.category} · {Math.round(food.macrosPerGram.carbs * 100)}g carbs/100g
              </p>
            </div>
            <span class="text-xl">{categoryIcons[food.category] || '🍽️'}</span>
          </button>
        {/each}
      </div>
    {:else if selectedCategory}
      <!-- Category foods -->
      <div>
        <button
          type="button"
          class="mb-3 flex items-center text-sm text-gray-400 hover:text-white"
          onclick={goBack}
        >
          <svg class="mr-1 h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 19l-7-7 7-7"
            />
          </svg>
          Back to categories
        </button>

        <h3 class="mb-2 text-sm font-medium text-gray-400">
          {categoryIcons[selectedCategory] || '🍽️'}
          {selectedCategory.charAt(0).toUpperCase() + selectedCategory.slice(1)}
        </h3>

        <div class="space-y-1">
          {#each categoryFoods as food (food.id)}
            <button
              type="button"
              class="flex w-full items-center justify-between rounded-lg px-4 py-3 text-left transition-colors {selected?.id ===
              food.id
                ? 'bg-purple-500/30'
                : 'hover:bg-gray-800'}"
              onclick={() => selectFood(food)}
            >
              <div>
                <p class="text-white">{food.name}</p>
                <p class="text-xs text-gray-400">
                  {Math.round(food.macrosPerGram.carbs * 100)}g carbs/100g
                </p>
              </div>
              {#if selected?.id === food.id}
                <svg class="h-5 w-5 text-purple-400" fill="currentColor" viewBox="0 0 20 20">
                  <path
                    fill-rule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clip-rule="evenodd"
                  />
                </svg>
              {/if}
            </button>
          {/each}
        </div>
      </div>
    {:else if showCategories}
      <!-- Category grid -->
      <div>
        <h3 class="mb-3 text-sm font-medium text-gray-400">Categories</h3>
        <div class="mb-6 grid grid-cols-4 gap-2">
          {#each categories as category (category)}
            <button
              type="button"
              class="flex flex-col items-center rounded-lg bg-gray-800 p-3 transition-colors hover:bg-gray-700"
              onclick={() => selectCategory(category)}
            >
              <span class="mb-1 text-2xl">{categoryIcons[category] || '🍽️'}</span>
              <span class="text-xs capitalize text-gray-300">{category}</span>
            </button>
          {/each}
        </div>

        <h3 class="mb-3 text-sm font-medium text-gray-400">Popular</h3>
        <div class="space-y-1">
          {#each popularFoods as food (food.id)}
            <button
              type="button"
              class="flex w-full items-center justify-between rounded-lg px-4 py-3 text-left transition-colors {selected?.id ===
              food.id
                ? 'bg-purple-500/30'
                : 'hover:bg-gray-800'}"
              onclick={() => selectFood(food)}
            >
              <div>
                <p class="text-white">{food.name}</p>
                <p class="text-xs text-gray-400">
                  {food.category} · {Math.round(food.macrosPerGram.carbs * 100)}g carbs/100g
                </p>
              </div>
              <span class="text-xl">{categoryIcons[food.category] || '🍽️'}</span>
            </button>
          {/each}
        </div>
      </div>
    {:else}
      <!-- Empty state -->
      <div class="flex flex-col items-center justify-center py-8 text-center text-gray-500">
        <svg class="mb-2 h-12 w-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="1.5"
            d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
          />
        </svg>
        <p class="text-sm">No results found</p>
        <p class="text-xs text-gray-600">Try a different search term</p>
      </div>
    {/if}
  </div>
</div>
