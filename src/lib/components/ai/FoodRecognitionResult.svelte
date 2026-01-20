<script lang="ts">
  /**
   * Food Recognition Result Component
   * Workstream A: AI-Powered Food Recognition
   *
   * Displays AI recognition results with editable macro values.
   */
  import type { FoodRecognitionResult, RecognizedFoodItem } from '$lib/types/ai';
  import type { MacroData } from '$lib/types/events';
  import FoodItemEditor from './FoodItemEditor.svelte';

  interface Props {
    result: FoodRecognitionResult;
    imageUrl?: string;
    onSave: (macros: MacroData, items: RecognizedFoodItem[]) => void;
    onCancel: () => void;
    saving?: boolean;
  }

  let { result, imageUrl, onSave, onCancel, saving = false }: Props = $props();

  // Make items editable - sync when result changes
  let editedItems = $state<RecognizedFoodItem[]>([...result.items]);

  // Sync editedItems when result prop changes (e.g., new recognition)
  $effect(() => {
    editedItems = [...result.items];
  });

  // Calculate totals from edited items
  let calculatedTotals = $derived.by(() => {
    const totals: MacroData = { calories: 0, carbs: 0, protein: 0, fat: 0 };
    for (const item of editedItems) {
      if (item.macros) {
        totals.calories += item.macros.calories ?? 0;
        totals.carbs += item.macros.carbs ?? 0;
        totals.protein += item.macros.protein ?? 0;
        totals.fat += item.macros.fat ?? 0;
      }
    }
    return totals;
  });

  function handleItemUpdate(index: number, updated: RecognizedFoodItem) {
    editedItems = editedItems.map((item, i) => (i === index ? updated : item));
  }

  function handleItemRemove(index: number) {
    editedItems = editedItems.filter((_, i) => i !== index);
  }

  function handleSave() {
    onSave(calculatedTotals, editedItems);
  }

  function confidenceColor(confidence: number): string {
    if (confidence >= 0.8) return 'text-green-400';
    if (confidence >= 0.5) return 'text-yellow-400';
    return 'text-red-400';
  }

  function confidenceLabel(confidence: number): string {
    if (confidence >= 0.8) return 'High';
    if (confidence >= 0.5) return 'Medium';
    return 'Low';
  }
</script>

<div class="flex flex-col">
  <!-- Header with image and confidence -->
  <div class="mb-4 flex items-start gap-4">
    {#if imageUrl}
      <img src={imageUrl} alt="Food" class="h-20 w-20 rounded-lg object-cover" />
    {/if}
    <div class="flex-1">
      <div class="mb-1 text-sm text-gray-400">
        Analyzed by {result.provider}
      </div>
      <div class="flex items-center gap-2">
        <span class="text-sm text-gray-500">Confidence:</span>
        <span class={`text-sm font-medium ${confidenceColor(result.confidence)}`}>
          {confidenceLabel(result.confidence)} ({Math.round(result.confidence * 100)}%)
        </span>
      </div>
      <div class="mt-1 text-xs text-gray-500">
        {result.processingTimeMs.toFixed(0)}ms
      </div>
    </div>
  </div>

  <!-- Total Macros Summary -->
  <div class="mb-4 rounded-lg bg-gray-800 p-4">
    <div class="mb-2 text-sm font-medium text-gray-400">Total Macros</div>
    <div class="grid grid-cols-4 gap-2 text-center">
      <div>
        <div class="text-2xl font-bold text-white">{Math.round(calculatedTotals.carbs)}</div>
        <div class="text-xs text-green-400">Carbs (g)</div>
      </div>
      <div>
        <div class="text-2xl font-bold text-white">{Math.round(calculatedTotals.protein)}</div>
        <div class="text-xs text-blue-400">Protein (g)</div>
      </div>
      <div>
        <div class="text-2xl font-bold text-white">{Math.round(calculatedTotals.fat)}</div>
        <div class="text-xs text-yellow-400">Fat (g)</div>
      </div>
      <div>
        <div class="text-2xl font-bold text-white">{Math.round(calculatedTotals.calories)}</div>
        <div class="text-xs text-gray-400">Calories</div>
      </div>
    </div>
  </div>

  <!-- Individual Items -->
  <div class="mb-4">
    <div class="mb-2 flex items-center justify-between">
      <span class="text-sm font-medium text-gray-400">
        Recognized Items ({editedItems.length})
      </span>
      <span class="text-xs text-gray-500">Tap to edit</span>
    </div>

    <div class="space-y-2">
      {#each editedItems as item, index (index)}
        <FoodItemEditor
          {item}
          onUpdate={(updated) => handleItemUpdate(index, updated)}
          onRemove={() => handleItemRemove(index)}
        />
      {/each}
    </div>

    {#if editedItems.length === 0}
      <div class="rounded-lg bg-gray-800/50 p-4 text-center text-gray-500">
        No items recognized. Add manually below.
      </div>
    {/if}
  </div>

  <!-- Action Buttons -->
  <div class="grid grid-cols-2 gap-3">
    <button
      type="button"
      onclick={onCancel}
      disabled={saving}
      class="rounded-lg bg-gray-700 py-3 text-center font-medium text-white transition-colors hover:bg-gray-600 disabled:opacity-50"
    >
      Cancel
    </button>

    <button
      type="button"
      onclick={handleSave}
      disabled={saving || editedItems.length === 0}
      class="rounded-lg bg-green-600 py-3 text-center font-medium text-white transition-colors hover:bg-green-500 disabled:opacity-50"
    >
      {#if saving}
        Saving...
      {:else}
        Log Meal
      {/if}
    </button>
  </div>
</div>
