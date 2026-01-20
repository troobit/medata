<script lang="ts">
  /**
   * EstimationResult - Display final macro estimation with edit capability.
   * Shows volume, weight, macros, and allows corrections.
   */
  import type { LocalEstimationResult } from '$lib/types/local-estimation';
  import { volumeCalculator } from '$lib/services/local-estimation';

  interface Props {
    result: LocalEstimationResult;
    onCarbsChange?: (carbs: number) => void;
    onSave?: () => void;
    editable?: boolean;
  }

  let { result, onCarbsChange, onSave, editable = true }: Props = $props();

  let editedCarbs = $state(result.estimatedMacros.carbs);
  let isEditing = $state(false);

  // Calculate uncertainty bounds
  const uncertainty = $derived(volumeCalculator.calculateUncertainty(result.volume));

  // Confidence level text
  const confidenceText = $derived(
    result.confidence > 0.8
      ? 'High'
      : result.confidence > 0.6
        ? 'Medium'
        : 'Low'
  );

  const confidenceColor = $derived(
    result.confidence > 0.8
      ? 'text-green-400'
      : result.confidence > 0.6
        ? 'text-yellow-400'
        : 'text-orange-400'
  );

  function handleCarbsInput(e: Event) {
    const input = e.target as HTMLInputElement;
    const value = parseFloat(input.value);
    if (!isNaN(value) && value >= 0) {
      editedCarbs = value;
    }
  }

  function incrementCarbs(amount: number) {
    editedCarbs = Math.max(0, Math.round((editedCarbs + amount) * 10) / 10);
  }

  function confirmEdit() {
    onCarbsChange?.(editedCarbs);
    isEditing = false;
  }

  function cancelEdit() {
    editedCarbs = result.estimatedMacros.carbs;
    isEditing = false;
  }

  // Reset edited value when result changes
  $effect(() => {
    editedCarbs = result.estimatedMacros.carbs;
  });
</script>

<div class="space-y-4">
  <!-- Food type header -->
  <div class="rounded-lg bg-gray-800/50 p-4">
    <div class="flex items-center justify-between">
      <div>
        <h3 class="font-medium text-white">{result.foodType.name}</h3>
        <p class="text-sm text-gray-400">{result.foodType.category}</p>
      </div>
      <div class="text-right">
        <p class="text-sm text-gray-400">Estimated weight</p>
        <p class="text-lg font-semibold text-white">{result.estimatedWeightGrams}g</p>
      </div>
    </div>
  </div>

  <!-- Volume info -->
  <div class="grid grid-cols-2 gap-3">
    <div class="rounded-lg bg-gray-800/30 p-3 text-center">
      <p class="text-xs text-gray-500">Volume</p>
      <p class="text-lg font-semibold text-purple-400">{result.volume.totalVolumeMl} mL</p>
      <p class="text-xs text-gray-500">
        {uncertainty.low}-{uncertainty.high} mL range
      </p>
    </div>
    <div class="rounded-lg bg-gray-800/30 p-3 text-center">
      <p class="text-xs text-gray-500">Confidence</p>
      <p class="text-lg font-semibold {confidenceColor}">
        {Math.round(result.confidence * 100)}%
      </p>
      <p class="text-xs text-gray-500">{confidenceText} accuracy</p>
    </div>
  </div>

  <!-- Macro breakdown -->
  <div class="rounded-lg bg-gray-800/50 p-4">
    <h4 class="mb-3 text-sm font-medium text-gray-400">Estimated Macros</h4>

    <!-- Carbs (primary, editable) -->
    <div class="mb-4 rounded-lg bg-green-500/10 p-4">
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium text-green-400">Carbs</span>
        {#if editable && !isEditing}
          <button
            type="button"
            class="text-xs text-gray-400 hover:text-white"
            onclick={() => (isEditing = true)}
          >
            Edit
          </button>
        {/if}
      </div>

      {#if isEditing}
        <div class="mt-2 flex items-center justify-center gap-2">
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 hover:bg-gray-600"
            onclick={() => incrementCarbs(-5)}
          >
            -5
          </button>
          <button
            type="button"
            class="flex h-8 w-8 items-center justify-center rounded-full bg-gray-700 text-gray-300 hover:bg-gray-600"
            onclick={() => incrementCarbs(-1)}
          >
            -
          </button>
          <input
            type="number"
            value={editedCarbs}
            oninput={handleCarbsInput}
            class="w-20 bg-transparent text-center text-3xl font-bold text-white focus:outline-none"
            min="0"
            step="0.1"
          />
          <button
            type="button"
            class="flex h-8 w-8 items-center justify-center rounded-full bg-gray-700 text-gray-300 hover:bg-gray-600"
            onclick={() => incrementCarbs(1)}
          >
            +
          </button>
          <button
            type="button"
            class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-gray-300 hover:bg-gray-600"
            onclick={() => incrementCarbs(5)}
          >
            +5
          </button>
        </div>
        <div class="mt-3 flex justify-center gap-2">
          <button
            type="button"
            class="rounded-lg bg-gray-700 px-4 py-1.5 text-sm text-gray-300 hover:bg-gray-600"
            onclick={cancelEdit}
          >
            Cancel
          </button>
          <button
            type="button"
            class="rounded-lg bg-green-600 px-4 py-1.5 text-sm text-white hover:bg-green-500"
            onclick={confirmEdit}
          >
            Confirm
          </button>
        </div>
      {:else}
        <p class="text-center text-4xl font-bold text-white">
          {editedCarbs}
          <span class="text-lg font-normal text-gray-400">g</span>
        </p>
      {/if}
    </div>

    <!-- Other macros -->
    <div class="grid grid-cols-3 gap-3">
      <div class="text-center">
        <p class="text-xs text-gray-500">Calories</p>
        <p class="text-lg font-semibold text-white">{result.estimatedMacros.calories}</p>
      </div>
      <div class="text-center">
        <p class="text-xs text-gray-500">Protein</p>
        <p class="text-lg font-semibold text-white">{result.estimatedMacros.protein}g</p>
      </div>
      <div class="text-center">
        <p class="text-xs text-gray-500">Fat</p>
        <p class="text-lg font-semibold text-white">{result.estimatedMacros.fat}g</p>
      </div>
    </div>
  </div>

  <!-- Warnings -->
  {#if result.volume.warnings && result.volume.warnings.length > 0}
    <div class="rounded-lg border border-yellow-500/30 bg-yellow-500/10 p-3">
      <p class="mb-1 text-sm font-medium text-yellow-400">Notes</p>
      <ul class="space-y-1 text-sm text-yellow-300/80">
        {#each result.volume.warnings as warning}
          <li>• {warning}</li>
        {/each}
      </ul>
    </div>
  {/if}

  <!-- Processing info -->
  <p class="text-center text-xs text-gray-600">
    Processed locally in {result.processingTimeMs}ms · ±{uncertainty.percentage}% uncertainty
  </p>

  <!-- Save button -->
  {#if onSave && !isEditing}
    <button
      type="button"
      class="mt-4 w-full rounded-lg bg-purple-600 py-3 font-medium text-white transition-colors hover:bg-purple-500"
      onclick={onSave}
    >
      Save {editedCarbs}g Carbs
    </button>
  {/if}
</div>
