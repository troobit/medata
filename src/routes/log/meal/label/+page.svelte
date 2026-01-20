<script lang="ts">
  /**
   * Nutrition Label Scanner Page
   * Workstream A: AI-Powered Food Recognition
   *
   * Scans nutrition labels to extract macro data automatically.
   */
  import { goto } from '$app/navigation';
  import { CameraCapture, PhotoPreview } from '$lib/components/ai';
  import { getFoodService } from '$lib/services/ai';
  import { compressImage, blobToDataUrl } from '$lib/utils/imageProcessing';
  import { settingsStore, eventsStore } from '$lib/stores';
  import type { NutritionLabelResult } from '$lib/types/ai';
  import { Button } from '$lib/components/ui';

  type FlowState = 'capture' | 'preview' | 'result';

  let flowState = $state<FlowState>('capture');
  let capturedImage = $state<Blob | null>(null);
  let imageUrl = $state<string | null>(null);
  let scanResult = $state<NutritionLabelResult | null>(null);
  let processing = $state(false);
  let saving = $state(false);
  let error = $state<string | null>(null);

  // Editable values
  let servings = $state(1);
  let carbs = $state(0);
  let protein = $state(0);
  let fat = $state(0);
  let calories = $state(0);

  let aiConfigured = $derived(settingsStore.isAIConfigured);

  async function handleCapture(blob: Blob) {
    error = null;
    try {
      capturedImage = await compressImage(blob, {
        maxWidth: 1024,
        maxHeight: 1024,
        quality: 0.9,
        format: 'image/jpeg'
      });
      imageUrl = await blobToDataUrl(capturedImage);
      flowState = 'preview';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to process image';
    }
  }

  function handleRetake() {
    capturedImage = null;
    imageUrl = null;
    scanResult = null;
    error = null;
    flowState = 'capture';
  }

  async function handleScan() {
    if (!capturedImage) return;

    error = null;
    processing = true;

    try {
      const service = getFoodService(settingsStore.settings);
      if (!service) {
        throw new Error('No AI provider configured');
      }

      scanResult = await service.parseNutritionLabel(capturedImage);

      // Populate editable values
      carbs = scanResult.macros.carbs ?? 0;
      protein = scanResult.macros.protein ?? 0;
      fat = scanResult.macros.fat ?? 0;
      calories = scanResult.macros.calories ?? 0;
      servings = 1;

      flowState = 'result';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Scan failed';
    } finally {
      processing = false;
    }
  }

  // Calculated values based on servings
  let adjustedCarbs = $derived(Math.round(carbs * servings));
  let adjustedProtein = $derived(Math.round(protein * servings));
  let adjustedFat = $derived(Math.round(fat * servings));
  let adjustedCalories = $derived(Math.round(calories * servings));

  async function handleSave() {
    saving = true;
    error = null;

    try {
      await eventsStore.logMeal(adjustedCarbs, {
        calories: adjustedCalories,
        protein: adjustedProtein,
        fat: adjustedFat,
        description: scanResult?.servingSize
          ? `${servings} serving${servings > 1 ? 's' : ''} (${scanResult.servingSize})`
          : undefined,
        source: 'ai',
        confidence: scanResult?.confidence
      });

      goto('/');
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save meal';
    } finally {
      saving = false;
    }
  }

  function handleCancel() {
    goto('/log/meal');
  }

  function confidenceColor(confidence: number): string {
    if (confidence >= 0.8) return 'text-green-400';
    if (confidence >= 0.5) return 'text-yellow-400';
    return 'text-red-400';
  }
</script>

<svelte:head>
  <title>Label Scanner - MeData</title>
</svelte:head>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-6">
    <a href="/log/meal" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
      <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back
    </a>
    <h1 class="text-2xl font-bold text-white">Nutrition Label Scanner</h1>
    <p class="mt-1 text-sm text-gray-400">
      {#if flowState === 'capture'}
        Take a photo of the nutrition label
      {:else if flowState === 'preview'}
        Review your photo
      {:else}
        Adjust values and save
      {/if}
    </p>
  </header>

  {#if !aiConfigured}
    <div class="flex flex-1 flex-col items-center justify-center text-center">
      <div
        class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-yellow-500/20 text-4xl"
      >
        ⚙️
      </div>
      <h2 class="mb-2 text-xl font-semibold text-white">AI Not Configured</h2>
      <p class="mb-6 max-w-sm text-gray-400">
        To scan nutrition labels, please add an API key in Settings.
      </p>
      <div class="flex gap-3">
        <Button href="/settings" variant="primary">Go to Settings</Button>
        <Button href="/log/meal" variant="secondary">Manual Entry</Button>
      </div>
    </div>
  {:else}
    <div class="flex flex-1 flex-col">
      {#if error}
        <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
          {error}
        </div>
      {/if}

      {#if flowState === 'capture'}
        <CameraCapture onCapture={handleCapture} onCancel={handleCancel} />
      {:else if flowState === 'preview' && capturedImage}
        <PhotoPreview
          image={capturedImage}
          onConfirm={handleScan}
          onRetake={handleRetake}
          {processing}
        />
      {:else if flowState === 'result' && scanResult}
        <!-- Result View -->
        <div class="flex flex-col">
          <!-- Image thumbnail and confidence -->
          <div class="mb-4 flex items-start gap-4">
            {#if imageUrl}
              <img src={imageUrl} alt="Label" class="h-20 w-20 rounded-lg object-cover" />
            {/if}
            <div class="flex-1">
              {#if scanResult.servingSize}
                <div class="text-sm text-white">
                  Serving: {scanResult.servingSize}
                </div>
              {/if}
              {#if scanResult.servingsPerContainer}
                <div class="text-sm text-gray-400">
                  {scanResult.servingsPerContainer} servings per container
                </div>
              {/if}
              <div class="mt-1 flex items-center gap-2">
                <span class="text-xs text-gray-500">Confidence:</span>
                <span class={`text-xs font-medium ${confidenceColor(scanResult.confidence)}`}>
                  {Math.round(scanResult.confidence * 100)}%
                </span>
              </div>
            </div>
          </div>

          <!-- Serving Multiplier -->
          <div class="mb-4 rounded-lg bg-gray-800 p-4">
            <label for="servings" class="mb-2 block text-sm font-medium text-gray-400">
              Number of Servings
            </label>
            <div class="flex items-center justify-center gap-3">
              <button
                type="button"
                onclick={() => (servings = Math.max(0.5, servings - 0.5))}
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-white"
              >
                -
              </button>
              <input
                id="servings"
                type="number"
                bind:value={servings}
                min="0.5"
                step="0.5"
                class="w-20 bg-transparent text-center text-2xl font-bold text-white focus:outline-none"
              />
              <button
                type="button"
                onclick={() => (servings = servings + 0.5)}
                class="flex h-10 w-10 items-center justify-center rounded-full bg-gray-700 text-xl text-white"
              >
                +
              </button>
            </div>
          </div>

          <!-- Per-Serving Macros (editable) -->
          <div class="mb-4 rounded-lg bg-gray-800/50 p-4">
            <div class="mb-2 text-xs text-gray-500">Per serving (tap to edit)</div>
            <div class="grid grid-cols-4 gap-2">
              <div>
                <label for="carbs" class="mb-1 block text-xs font-medium text-green-400"
                  >Carbs</label
                >
                <input
                  id="carbs"
                  type="number"
                  bind:value={carbs}
                  min="0"
                  class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-green-500"
                />
              </div>
              <div>
                <label for="protein" class="mb-1 block text-xs font-medium text-blue-400"
                  >Protein</label
                >
                <input
                  id="protein"
                  type="number"
                  bind:value={protein}
                  min="0"
                  class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-blue-500"
                />
              </div>
              <div>
                <label for="fat" class="mb-1 block text-xs font-medium text-yellow-400">Fat</label>
                <input
                  id="fat"
                  type="number"
                  bind:value={fat}
                  min="0"
                  class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-yellow-500"
                />
              </div>
              <div>
                <label for="calories" class="mb-1 block text-xs font-medium text-gray-400"
                  >Calories</label
                >
                <input
                  id="calories"
                  type="number"
                  bind:value={calories}
                  min="0"
                  class="w-full rounded bg-gray-900 px-2 py-2 text-center text-white focus:outline-none focus:ring-1 focus:ring-gray-500"
                />
              </div>
            </div>
          </div>

          <!-- Calculated Total -->
          <div class="mb-6 rounded-lg bg-green-500/10 p-4">
            <div class="mb-2 text-sm font-medium text-green-400">
              Total for {servings} serving{servings !== 1 ? 's' : ''}
            </div>
            <div class="grid grid-cols-4 gap-2 text-center">
              <div>
                <div class="text-2xl font-bold text-white">{adjustedCarbs}</div>
                <div class="text-xs text-green-400">Carbs (g)</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-white">{adjustedProtein}</div>
                <div class="text-xs text-blue-400">Protein (g)</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-white">{adjustedFat}</div>
                <div class="text-xs text-yellow-400">Fat (g)</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-white">{adjustedCalories}</div>
                <div class="text-xs text-gray-400">Calories</div>
              </div>
            </div>
          </div>

          <!-- Additional Info -->
          {#if scanResult.fiber || scanResult.sugar || scanResult.sodium}
            <div class="mb-4 rounded-lg bg-gray-800/50 p-3 text-sm">
              <div class="text-xs text-gray-500 mb-1">Additional per serving:</div>
              <div class="flex flex-wrap gap-3 text-gray-400">
                {#if scanResult.fiber}
                  <span>Fiber: {scanResult.fiber}g</span>
                {/if}
                {#if scanResult.sugar}
                  <span>Sugar: {scanResult.sugar}g</span>
                {/if}
                {#if scanResult.sodium}
                  <span>Sodium: {scanResult.sodium}mg</span>
                {/if}
              </div>
            </div>
          {/if}

          <!-- Action Buttons -->
          <div class="grid grid-cols-2 gap-3">
            <button
              type="button"
              onclick={handleRetake}
              disabled={saving}
              class="rounded-lg bg-gray-700 py-3 text-center font-medium text-white transition-colors hover:bg-gray-600 disabled:opacity-50"
            >
              Rescan
            </button>
            <button
              type="button"
              onclick={handleSave}
              disabled={saving}
              class="rounded-lg bg-green-600 py-3 text-center font-medium text-white transition-colors hover:bg-green-500 disabled:opacity-50"
            >
              {saving ? 'Saving...' : 'Log Meal'}
            </button>
          </div>
        </div>
      {/if}
    </div>
  {/if}
</div>
