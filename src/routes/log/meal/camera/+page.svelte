<script lang="ts">
  /**
   * Unified Camera Entry Page
   * Consolidates AI Photo, Volume Estimation, and Label Scanning into a single flow
   *
   * Flow: Mode Selection -> Capture -> Process (varies by mode)
   */
  import { goto } from '$app/navigation';
  import { CameraCapture, PhotoPreview, FoodRecognitionResult } from '$lib/components/ai';
  import {
    FoodRegionSelector,
    FoodTypeSelector,
    EstimationResult
  } from '$lib/components/local-estimation';
  import { RecogniseFoodWithFallback, getFoodService } from '$lib/services/ai';
  import { estimationEngine, volumeCalculator } from '$lib/services/local-estimation';
  import { compressImage, blobToDataUrl } from '$lib/utils/imageProcessing';
  import { settingsStore, eventsStore, validationStore } from '$lib/stores';
  import { Button } from '$lib/components/ui';
  import type {
    FoodRecognitionResult as FoodRecognitionResultType,
    RecognisedFoodItem,
    NutritionLabelResult
  } from '$lib/types/ai';
  import type { MacroData } from '$lib/types/events';
  import type {
    FoodRegion,
    FoodDensityEntry,
    DetectedReference,
    LocalEstimationResult
  } from '$lib/types/local-estimation';

  // Processing modes
  type ProcessingMode = 'ai' | 'estimate' | 'label';

  // Flow states
  type FlowState =
    | 'mode-select'
    | 'capture'
    | 'preview'
    | 'ai-result'
    | 'estimate-region'
    | 'estimate-food-type'
    | 'estimate-result'
    | 'label-result';

  // Mode configuration
  const modes: Array<{
    id: ProcessingMode;
    icon: string;
    label: string;
    description: string;
    colour: string;
    bgColour: string;
    requiresAI: boolean;
  }> = [
    {
      id: 'ai',
      icon: '🤖',
      label: 'AI Analysis',
      description: 'AI identifies food and estimates macros',
      colour: 'text-blue-400',
      bgColour: 'bg-blue-500/10 hover:bg-blue-500/20',
      requiresAI: true
    },
    {
      id: 'estimate',
      icon: '📐',
      label: 'Volume Estimate',
      description: 'Use reference card for local calculation',
      colour: 'text-purple-400',
      bgColour: 'bg-purple-500/10 hover:bg-purple-500/20',
      requiresAI: false
    },
    {
      id: 'label',
      icon: '🏷️',
      label: 'Scan Label',
      description: 'Read nutrition facts from packaging',
      colour: 'text-green-400',
      bgColour: 'bg-green-500/10 hover:bg-green-500/20',
      requiresAI: true
    }
  ];

  // State
  let selectedMode = $state<ProcessingMode>('ai');
  let flowState = $state<FlowState>('capture');
  let capturedImage = $state<Blob | null>(null);
  let imageUrl = $state<string | null>(null);
  let processing = $state(false);
  let saving = $state(false);
  let error = $state<string | null>(null);

  // AI recognition state
  let recognitionResult = $state<FoodRecognitionResultType | null>(null);

  // Volume estimation state
  let reference = $state<DetectedReference | null>(null);
  let regions = $state<FoodRegion[]>([]);
  let selectedFood = $state<FoodDensityEntry | null>(null);
  let estimationResult = $state<LocalEstimationResult | null>(null);
  let finalCarbs = $state<number>(0);
  let detecting = $state(false);

  // Label scanning state
  let scanResult = $state<NutritionLabelResult | null>(null);
  let servings = $state(1);
  let carbs = $state(0);
  let protein = $state(0);
  let fat = $state(0);
  let calories = $state(0);

  // Check if AI is configured
  let aiConfigured = $derived(settingsStore.isAIConfigured);

  // Calculated values for label scanning
  let adjustedCarbs = $derived(Math.round(carbs * servings));
  let adjustedProtein = $derived(Math.round(protein * servings));
  let adjustedFat = $derived(Math.round(fat * servings));
  let adjustedCalories = $derived(Math.round(calories * servings));

  // Mode requires AI but AI not configured
  let _modeRequiresAI = $derived(modes.find((m) => m.id === selectedMode)?.requiresAI ?? false);

  function selectMode(mode: ProcessingMode) {
    selectedMode = mode;
    // If mode requires AI but not configured, show warning instead of proceeding
    if (modes.find((m) => m.id === mode)?.requiresAI && !aiConfigured) {
      return;
    }
    flowState = 'capture';
  }

  async function handleCapture(blob: Blob) {
    error = null;
    try {
      capturedImage = await compressImage(blob, {
        maxWidth: 1024,
        maxHeight: 1024,
        quality: selectedMode === 'label' ? 0.9 : 0.85,
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
    recognitionResult = null;
    scanResult = null;
    estimationResult = null;
    reference = null;
    regions = [];
    selectedFood = null;
    error = null;
    flowState = 'capture';
  }

  async function handleConfirm() {
    if (!capturedImage) return;

    error = null;
    processing = true;

    try {
      switch (selectedMode) {
        case 'ai':
          recognitionResult = await RecogniseFoodWithFallback(
            capturedImage,
            settingsStore.settings
          );
          flowState = 'ai-result';
          break;

        case 'estimate':
          // Try to detect reference object
          detecting = true;
          try {
            reference = await estimationEngine.detectReference(capturedImage);
          } catch (err) {
            console.warn('Reference detection failed:', err);
          }
          detecting = false;
          flowState = 'estimate-region';
          break;

        case 'label': {
          const service = getFoodService(settingsStore.settings);
          if (!service) {
            throw new Error('No AI provider configured');
          }
          scanResult = await service.parseNutritionLabel(capturedImage);
          carbs = scanResult.macros.carbs ?? 0;
          protein = scanResult.macros.protein ?? 0;
          fat = scanResult.macros.fat ?? 0;
          calories = scanResult.macros.calories ?? 0;
          servings = 1;
          flowState = 'label-result';
          break;
        }
      }
    } catch (e) {
      error = e instanceof Error ? e.message : 'Processing failed';
    } finally {
      processing = false;
    }
  }

  // Volume estimation handlers
  function handleRegionsChange(newRegions: FoodRegion[]) {
    regions = newRegions;
  }

  function proceedToFoodType() {
    if (regions.length === 0) {
      error = 'Please draw around the food first';
      return;
    }
    error = null;
    flowState = 'estimate-food-type';
  }

  async function handleFoodSelect(food: FoodDensityEntry) {
    selectedFood = food;
    await calculateEstimate();
  }

  async function calculateEstimate() {
    if (!capturedImage || !selectedFood || regions.length === 0) return;

    error = null;
    try {
      const shape = volumeCalculator.suggestShape(selectedFood.name);
      estimationResult = await estimationEngine.estimate(
        capturedImage,
        regions,
        selectedFood,
        shape
      );
      finalCarbs = estimationResult.estimatedMacros.carbs;
      flowState = 'estimate-result';
    } catch (err) {
      console.error('Estimation error:', err);
      error = 'Failed to estimate. Please try again.';
    }
  }

  function handleCarbsChange(carbValue: number) {
    finalCarbs = carbValue;
    if (estimationResult) {
      estimationEngine.recordUserCorrection(estimationResult, carbValue);
    }
  }

  // Save handlers
  async function handleAISave(macros: MacroData, items: RecognisedFoodItem[]) {
    saving = true;
    error = null;

    try {
      const event = await eventsStore.logMeal(macros.carbs, {
        calories: macros.calories,
        protein: macros.protein,
        fat: macros.fat,
        items: items.map((item) => ({
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          macros: item.macros
        })),
        source: 'ai',
        confidence: recognitionResult?.confidence,
        photoUrl: imageUrl ?? undefined
      });

      // Record correction if user edited the AI prediction
      if (recognitionResult) {
        const original = recognitionResult.totalMacros;
        const hasCorrection =
          Math.abs(original.carbs - macros.carbs) > 0.5 ||
          Math.abs(original.protein - macros.protein) > 0.5 ||
          Math.abs(original.fat - macros.fat) > 0.5 ||
          Math.abs(original.calories - macros.calories) > 1;

        if (hasCorrection) {
          await validationStore.recordCorrection(event.id, original, macros, {
            imageUrl: imageUrl ?? undefined,
            aiProvider: recognitionResult.provider,
            aiConfidence: recognitionResult.confidence
          });
        }
      }

      goto('/');
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save meal';
    } finally {
      saving = false;
    }
  }

  async function saveEstimationResult() {
    if (!estimationResult) return;

    saving = true;
    error = null;
    try {
      await eventsStore.logMeal(finalCarbs, {
        protein: estimationResult.estimatedMacros.protein,
        fat: estimationResult.estimatedMacros.fat,
        calories: estimationResult.estimatedMacros.calories,
        description: estimationResult.foodType.name,
        source: 'local-estimation',
        confidence: estimationResult.confidence,
        photoUrl: imageUrl ?? undefined
      });
      goto('/');
    } catch {
      error = 'Failed to save meal';
    } finally {
      saving = false;
    }
  }

  async function saveLabelResult() {
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
        confidence: scanResult?.confidence,
        photoUrl: imageUrl ?? undefined
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

  function goBack() {
    error = null;
    switch (flowState) {
      case 'capture':
        flowState = 'mode-select';
        break;
      case 'preview':
        handleRetake();
        break;
      case 'ai-result':
      case 'label-result':
        flowState = 'preview';
        break;
      case 'estimate-region':
        flowState = 'preview';
        break;
      case 'estimate-food-type':
        flowState = 'estimate-region';
        break;
      case 'estimate-result':
        flowState = 'estimate-food-type';
        break;
      default:
        flowState = 'capture';
    }
  }

  function confidenceColor(confidence: number): string {
    if (confidence >= 0.8) return 'text-green-400';
    if (confidence >= 0.5) return 'text-yellow-400';
    return 'text-red-400';
  }

  // Page title based on current state
  let pageTitle = $derived.by(() => {
    switch (flowState) {
      case 'mode-select':
        return 'Choose Method';
      case 'capture':
        return modes.find((m) => m.id === selectedMode)?.label ?? 'Take Photo';
      case 'preview':
        return 'Review Photo';
      case 'ai-result':
        return 'AI Results';
      case 'estimate-region':
        return 'Select Food';
      case 'estimate-food-type':
        return 'Food Type';
      case 'estimate-result':
        return 'Estimation';
      case 'label-result':
        return 'Label Results';
      default:
        return 'Camera';
    }
  });

  // Cleanup on unmount
  $effect(() => {
    return () => {
      if (imageUrl) {
        URL.revokeObjectURL(imageUrl);
      }
    };
  });
</script>

<svelte:head>
  <title>Camera - MeData</title>
</svelte:head>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <!-- Header -->
  <header class="mb-4">
    <div class="mb-4 flex items-center justify-between">
      {#if flowState === 'mode-select' || flowState === 'capture'}
        <a href="/log/meal" class="inline-flex items-center text-gray-400 hover:text-gray-200">
          <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 19l-7-7 7-7"
            />
          </svg>
          Back
        </a>
      {:else}
        <button
          type="button"
          class="inline-flex items-center text-gray-400 hover:text-gray-200"
          onclick={goBack}
        >
          <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 19l-7-7 7-7"
            />
          </svg>
          Back
        </button>
      {/if}

      {#if flowState !== 'mode-select' && flowState !== 'capture'}
        <button
          type="button"
          class="text-sm text-gray-500 hover:text-gray-300"
          onclick={handleRetake}
        >
          Start over
        </button>
      {/if}
    </div>

    <h1 class="text-xl font-bold text-white">{pageTitle}</h1>

    <!-- Mode indicator when past mode selection -->
    {#if flowState !== 'mode-select'}
      <div class="mt-2 flex items-center gap-2">
        <span class="text-lg">{modes.find((m) => m.id === selectedMode)?.icon}</span>
        <span class={modes.find((m) => m.id === selectedMode)?.colour}>
          {modes.find((m) => m.id === selectedMode)?.label}
        </span>
        {#if flowState === 'capture'}
          <button
            type="button"
            class="ml-auto text-xs text-gray-500 hover:text-gray-300"
            onclick={() => (flowState = 'mode-select')}
          >
            Change
          </button>
        {/if}
      </div>
    {/if}
  </header>

  <!-- Error display -->
  {#if error}
    <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
      {error}
    </div>
  {/if}

  <!-- Main content -->
  <div class="flex flex-1 flex-col">
    {#if flowState === 'mode-select'}
      <!-- Mode Selection -->
      <div class="flex flex-1 flex-col">
        <p class="mb-4 text-sm text-gray-400">How do you want to log this meal?</p>

        <div class="space-y-3">
          {#each modes as mode}
            <button
              type="button"
              class="flex w-full items-start gap-4 rounded-lg p-4 text-left transition-colors {mode.bgColour} {selectedMode ===
              mode.id
                ? 'ring-2 ring-white/20'
                : ''}"
              onclick={() => selectMode(mode.id)}
              disabled={mode.requiresAI && !aiConfigured}
            >
              <span class="text-3xl">{mode.icon}</span>
              <div class="flex-1">
                <div class="flex items-center gap-2">
                  <span class="font-medium {mode.colour}">{mode.label}</span>
                  {#if mode.requiresAI && !aiConfigured}
                    <span class="rounded bg-yellow-500/20 px-1.5 py-0.5 text-xs text-yellow-400">
                      Needs API key
                    </span>
                  {/if}
                </div>
                <p class="mt-1 text-sm text-gray-400">{mode.description}</p>
              </div>
              <svg
                class="h-5 w-5 {mode.colour} mt-1"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 5l7 7-7 7"
                />
              </svg>
            </button>
          {/each}
        </div>

        {#if !aiConfigured}
          <div class="mt-6 rounded-lg bg-gray-800/50 p-4">
            <p class="text-sm text-gray-400">
              AI features require an API key.
              <a href="/settings" class="text-blue-400 hover:underline">Configure in Settings</a>
            </p>
          </div>
        {/if}
      </div>
    {:else if flowState === 'capture'}
      <!-- Camera Capture -->
      <CameraCapture onCapture={handleCapture} onCancel={handleCancel} />
    {:else if flowState === 'preview' && capturedImage}
      <!-- Photo Preview -->
      <PhotoPreview
        image={capturedImage}
        onConfirm={handleConfirm}
        onRetake={handleRetake}
        {processing}
      />
    {:else if flowState === 'ai-result' && recognitionResult}
      <!-- AI Recognition Result -->
      <FoodRecognitionResult
        result={recognitionResult}
        imageUrl={imageUrl ?? undefined}
        onSave={handleAISave}
        onCancel={handleRetake}
        {saving}
      />
    {:else if flowState === 'estimate-region' && imageUrl}
      <!-- Volume Estimation: Region Selection -->
      <div class="flex flex-1 flex-col">
        {#if detecting}
          <div class="flex flex-1 items-center justify-center">
            <div class="text-center">
              <div
                class="mx-auto mb-3 h-8 w-8 animate-spin rounded-full border-2 border-purple-500 border-t-transparent"
              ></div>
              <p class="text-gray-400">Detecting reference card...</p>
            </div>
          </div>
        {:else}
          <!-- Reference status -->
          <div
            class="mb-3 rounded-lg px-3 py-2 {reference ? 'bg-green-500/10' : 'bg-yellow-500/10'}"
          >
            {#if reference}
              <p class="text-sm text-green-400">
                {reference.type === 'credit-card' ? 'Card' : 'Coin'} detected ({Math.round(
                  reference.confidence * 100
                )}% confidence)
              </p>
            {:else}
              <p class="text-sm text-yellow-400">
                No reference detected. Estimates may be less accurate.
              </p>
            {/if}
          </div>

          <FoodRegionSelector {imageUrl} {regions} onRegionsChange={handleRegionsChange} />

          <div class="mt-auto pt-4">
            <Button
              variant="primary"
              size="lg"
              class="w-full"
              onclick={proceedToFoodType}
              disabled={regions.length === 0}
            >
              {regions.length === 0 ? 'Draw around food' : 'Continue'}
            </Button>
          </div>
        {/if}
      </div>
    {:else if flowState === 'estimate-food-type'}
      <!-- Volume Estimation: Food Type Selection -->
      <div class="flex flex-1 flex-col">
        <FoodTypeSelector selected={selectedFood} onSelect={handleFoodSelect} />
      </div>
    {:else if flowState === 'estimate-result' && estimationResult}
      <!-- Volume Estimation: Result -->
      <div class="flex flex-1 flex-col">
        {#if imageUrl}
          <div class="mb-4 h-32 overflow-hidden rounded-lg">
            <img src={imageUrl} alt="Food" class="h-full w-full object-cover" />
          </div>
        {/if}

        <EstimationResult
          result={estimationResult}
          onCarbsChange={handleCarbsChange}
          onSave={saveEstimationResult}
        />
      </div>
    {:else if flowState === 'label-result' && scanResult}
      <!-- Label Scanning Result -->
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
              <label for="carbs" class="mb-1 block text-xs font-medium text-green-400">Carbs</label>
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
            <div class="mb-1 text-xs text-gray-500">Additional per serving:</div>
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
            onclick={saveLabelResult}
            disabled={saving}
            class="rounded-lg bg-green-600 py-3 text-center font-medium text-white transition-colors hover:bg-green-500 disabled:opacity-50"
          >
            {saving ? 'Saving...' : 'Log Meal'}
          </button>
        </div>
      </div>
    {/if}
  </div>
</div>
