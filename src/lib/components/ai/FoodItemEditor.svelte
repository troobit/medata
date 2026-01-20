<script lang="ts">
  /**
   * Food Item Editor Component
   * Workstream A: AI-Powered Food Recognition
   *
   * Allows editing individual food item macros.
   */
  import type { RecognizedFoodItem } from '$lib/types/ai';

  interface Props {
    item: RecognizedFoodItem;
    onUpdate: (item: RecognizedFoodItem) => void;
    onRemove: () => void;
  }

  let { item, onUpdate, onRemove }: Props = $props();

  let expanded = $state(false);

  // Local editing state - initialized from props and synced via effects
  let name = $state(item.name);
  let quantity = $state(item.quantity ?? 1);
  let unit = $state(item.unit ?? 'serving');
  let carbs = $state(item.macros?.carbs ?? 0);
  let protein = $state(item.macros?.protein ?? 0);
  let fat = $state(item.macros?.fat ?? 0);
  let calories = $state(item.macros?.calories ?? 0);

  // Sync local state when item prop changes (e.g., from parent reset)
  $effect(() => {
    name = item.name;
    quantity = item.quantity ?? 1;
    unit = item.unit ?? 'serving';
    carbs = item.macros?.carbs ?? 0;
    protein = item.macros?.protein ?? 0;
    fat = item.macros?.fat ?? 0;
    calories = item.macros?.calories ?? 0;
  });

  function handleUpdate() {
    onUpdate({
      ...item,
      name,
      quantity,
      unit,
      macros: { carbs, protein, fat, calories }
    });
  }

  function confidenceColor(confidence: number): string {
    if (confidence >= 0.8) return 'bg-green-500/20 text-green-400';
    if (confidence >= 0.5) return 'bg-yellow-500/20 text-yellow-400';
    return 'bg-red-500/20 text-red-400';
  }
</script>

<div class="rounded-lg bg-gray-800/50 overflow-hidden">
  <!-- Collapsed View -->
  <button
    type="button"
    onclick={() => (expanded = !expanded)}
    class="flex w-full items-center gap-3 p-3 text-left hover:bg-gray-700/50"
  >
    <div class="flex-1">
      <div class="flex items-center gap-2">
        <span class="font-medium text-white">{name}</span>
        <span class={`rounded px-1.5 py-0.5 text-xs ${confidenceColor(item.confidence)}`}>
          {Math.round(item.confidence * 100)}%
        </span>
      </div>
      <div class="text-sm text-gray-400">
        {quantity}
        {unit} &middot; {carbs}g carbs
      </div>
    </div>
    <svg
      class="h-5 w-5 text-gray-400 transition-transform {expanded ? 'rotate-180' : ''}"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
    </svg>
  </button>

  <!-- Expanded Editor -->
  {#if expanded}
    <div class="border-t border-gray-700 p-3 space-y-3">
      <!-- Name -->
      <div>
        <label for="item-name-{item.name}" class="mb-1 block text-xs font-medium text-gray-400">
          Name
        </label>
        <input
          id="item-name-{item.name}"
          type="text"
          bind:value={name}
          onchange={handleUpdate}
          class="w-full rounded bg-gray-900 px-3 py-2 text-white focus:outline-none focus:ring-1 focus:ring-blue-500"
        />
      </div>

      <!-- Quantity and Unit -->
      <div class="grid grid-cols-2 gap-2">
        <div>
          <label for="item-qty-{item.name}" class="mb-1 block text-xs font-medium text-gray-400">
            Quantity
          </label>
          <input
            id="item-qty-{item.name}"
            type="number"
            bind:value={quantity}
            onchange={handleUpdate}
            min="0"
            step="0.5"
            class="w-full rounded bg-gray-900 px-3 py-2 text-white focus:outline-none focus:ring-1 focus:ring-blue-500"
          />
        </div>
        <div>
          <label for="item-unit-{item.name}" class="mb-1 block text-xs font-medium text-gray-400">
            Unit
          </label>
          <select
            id="item-unit-{item.name}"
            bind:value={unit}
            onchange={handleUpdate}
            class="w-full rounded bg-gray-900 px-3 py-2 text-white focus:outline-none focus:ring-1 focus:ring-blue-500"
          >
            <option value="g">grams (g)</option>
            <option value="ml">milliliters (ml)</option>
            <option value="oz">ounces (oz)</option>
            <option value="cup">cup</option>
            <option value="tbsp">tablespoon</option>
            <option value="piece">piece</option>
            <option value="serving">serving</option>
          </select>
        </div>
      </div>

      <!-- Macros -->
      <div class="grid grid-cols-4 gap-2">
        <div>
          <label for="item-carbs-{item.name}" class="mb-1 block text-xs font-medium text-green-400">
            Carbs
          </label>
          <input
            id="item-carbs-{item.name}"
            type="number"
            bind:value={carbs}
            onchange={handleUpdate}
            min="0"
            step="1"
            class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-green-500"
          />
        </div>
        <div>
          <label
            for="item-protein-{item.name}"
            class="mb-1 block text-xs font-medium text-blue-400"
          >
            Protein
          </label>
          <input
            id="item-protein-{item.name}"
            type="number"
            bind:value={protein}
            onchange={handleUpdate}
            min="0"
            step="1"
            class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-blue-500"
          />
        </div>
        <div>
          <label for="item-fat-{item.name}" class="mb-1 block text-xs font-medium text-yellow-400">
            Fat
          </label>
          <input
            id="item-fat-{item.name}"
            type="number"
            bind:value={fat}
            onchange={handleUpdate}
            min="0"
            step="1"
            class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-yellow-500"
          />
        </div>
        <div>
          <label for="item-cal-{item.name}" class="mb-1 block text-xs font-medium text-gray-400">
            Calories
          </label>
          <input
            id="item-cal-{item.name}"
            type="number"
            bind:value={calories}
            onchange={handleUpdate}
            min="0"
            step="10"
            class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-gray-500"
          />
        </div>
      </div>

      <!-- Remove Button -->
      <button
        type="button"
        onclick={onRemove}
        class="w-full rounded bg-red-500/20 py-2 text-sm text-red-400 hover:bg-red-500/30"
      >
        Remove Item
      </button>
    </div>
  {/if}
</div>
