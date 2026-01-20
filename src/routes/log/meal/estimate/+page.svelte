<script lang="ts">
  /**
   * Workstream C: Local Food Volume Estimation
   * Branch: dev-3
   *
   * Multi-step flow for browser-local food volume estimation:
   * 1. Capture photo with reference object
   * 2. Select food region
   * 3. Choose food type
   * 4. Review and save estimation
   */
  import { goto } from '$app/navigation';
  import { Button } from '$lib/components/ui';
  import {
    ReferenceCardGuide,
    FoodRegionSelector,
    FoodTypeSelector,
    EstimationResult
  } from '$lib/components/local-estimation';
  import { estimationEngine, volumeCalculator } from '$lib/services/local-estimation';
  import { eventsStore } from '$lib/stores';
  import type { FoodRegion, FoodDensityEntry, DetectedReference, LocalEstimationResult } from '$lib/types/local-estimation';
  import type { ShapeTemplate } from '$lib/services/local-estimation';

  // Flow steps
  type Step = 'capture' | 'region' | 'food-type' | 'result';

  let currentStep = $state<Step>('capture');
  let imageBlob = $state<Blob | null>(null);
  let imageUrl = $state<string | null>(null);
  let reference = $state<DetectedReference | null>(null);
  let regions = $state<FoodRegion[]>([]);
  let selectedFood = $state<FoodDensityEntry | null>(null);
  let result = $state<LocalEstimationResult | null>(null);
  let finalCarbs = $state<number>(0);
  let saving = $state(false);
  let detecting = $state(false);
  let error = $state<string | null>(null);

  // Camera state
  let videoRef: HTMLVideoElement;
  let stream: MediaStream | null = null;
  let cameraActive = $state(false);
  let cameraError = $state<string | null>(null);

  async function startCamera() {
    try {
      cameraError = null;
      stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: 'environment',
          width: { ideal: 1280 },
          height: { ideal: 720 }
        }
      });

      if (videoRef) {
        videoRef.srcObject = stream;
        await videoRef.play();
        cameraActive = true;
      }
    } catch (err) {
      console.error('Camera error:', err);
      cameraError = 'Could not access camera. Please try uploading a photo instead.';
    }
  }

  function stopCamera() {
    if (stream) {
      stream.getTracks().forEach((track) => track.stop());
      stream = null;
    }
    cameraActive = false;
  }

  async function capturePhoto() {
    if (!videoRef || !cameraActive) return;

    const canvas = document.createElement('canvas');
    canvas.width = videoRef.videoWidth;
    canvas.height = videoRef.videoHeight;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.drawImage(videoRef, 0, 0);

    canvas.toBlob(async (blob) => {
      if (blob) {
        await processImage(blob);
      }
    }, 'image/jpeg', 0.9);
  }

  async function handleFileSelect(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      await processImage(file);
    }
  }

  async function processImage(blob: Blob) {
    imageBlob = blob;
    imageUrl = URL.createObjectURL(blob);
    stopCamera();

    // Try to detect reference object
    detecting = true;
    error = null;
    try {
      reference = await estimationEngine.detectReference(blob);
    } catch (err) {
      console.warn('Reference detection failed:', err);
    }
    detecting = false;

    currentStep = 'region';
  }

  function handleRegionsChange(newRegions: FoodRegion[]) {
    regions = newRegions;
  }

  function proceedToFoodType() {
    if (regions.length === 0) {
      error = 'Please draw around the food first';
      return;
    }
    error = null;
    currentStep = 'food-type';
  }

  async function handleFoodSelect(food: FoodDensityEntry) {
    selectedFood = food;
    await calculateEstimate();
  }

  async function calculateEstimate() {
    if (!imageBlob || !selectedFood || regions.length === 0) return;

    error = null;
    try {
      const shape = volumeCalculator.suggestShape(selectedFood.name);
      result = await estimationEngine.estimate(imageBlob, regions, selectedFood, shape);
      finalCarbs = result.estimatedMacros.carbs;
      currentStep = 'result';
    } catch (err) {
      console.error('Estimation error:', err);
      error = 'Failed to estimate. Please try again.';
    }
  }

  function handleCarbsChange(carbs: number) {
    finalCarbs = carbs;
    // Record correction for learning
    if (result) {
      estimationEngine.recordUserCorrection(result, carbs);
    }
  }

  async function saveResult() {
    if (!result) return;

    saving = true;
    error = null;
    try {
      await eventsStore.logMeal(finalCarbs, {
        protein: result.estimatedMacros.protein,
        fat: result.estimatedMacros.fat,
        calories: result.estimatedMacros.calories,
        description: result.foodType.name,
        source: 'local-estimation',
        confidence: result.confidence
      });
      goto('/');
    } catch (err) {
      error = 'Failed to save meal';
    } finally {
      saving = false;
    }
  }

  function goBack() {
    error = null;
    switch (currentStep) {
      case 'region':
        imageBlob = null;
        if (imageUrl) {
          URL.revokeObjectURL(imageUrl);
          imageUrl = null;
        }
        regions = [];
        reference = null;
        currentStep = 'capture';
        break;
      case 'food-type':
        selectedFood = null;
        currentStep = 'region';
        break;
      case 'result':
        result = null;
        currentStep = 'food-type';
        break;
    }
  }

  function restart() {
    stopCamera();
    imageBlob = null;
    if (imageUrl) {
      URL.revokeObjectURL(imageUrl);
      imageUrl = null;
    }
    reference = null;
    regions = [];
    selectedFood = null;
    result = null;
    error = null;
    currentStep = 'capture';
  }

  // Cleanup on unmount
  $effect(() => {
    return () => {
      stopCamera();
      if (imageUrl) {
        URL.revokeObjectURL(imageUrl);
      }
    };
  });

  // Step titles
  const stepTitles: Record<Step, string> = {
    capture: 'Take Photo',
    region: 'Select Food',
    'food-type': 'Food Type',
    result: 'Estimation'
  };

  const stepNumbers: Record<Step, number> = {
    capture: 1,
    region: 2,
    'food-type': 3,
    result: 4
  };
</script>

<svelte:head>
  <title>Volume Estimation - MeData</title>
</svelte:head>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <!-- Header -->
  <header class="mb-4">
    <div class="mb-4 flex items-center justify-between">
      {#if currentStep === 'capture'}
        <a href="/log/meal" class="inline-flex items-center text-gray-400 hover:text-gray-200">
          <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
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
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          Back
        </button>
      {/if}

      <button
        type="button"
        class="text-sm text-gray-500 hover:text-gray-300"
        onclick={restart}
      >
        Start over
      </button>
    </div>

    <h1 class="text-xl font-bold text-white">{stepTitles[currentStep]}</h1>

    <!-- Progress indicator -->
    <div class="mt-3 flex gap-1">
      {#each Object.entries(stepNumbers) as [step, num]}
        <div
          class="h-1 flex-1 rounded-full transition-colors {stepNumbers[currentStep] >= num
            ? 'bg-purple-500'
            : 'bg-gray-700'}"
        ></div>
      {/each}
    </div>
  </header>

  <!-- Error display -->
  {#if error}
    <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
      {error}
    </div>
  {/if}

  <!-- Step content -->
  <div class="flex flex-1 flex-col">
    {#if currentStep === 'capture'}
      <!-- Camera / Upload step -->
      <div class="flex flex-1 flex-col">
        {#if cameraActive}
          <div class="relative mb-4 overflow-hidden rounded-lg">
            <video
              bind:this={videoRef}
              class="w-full"
              autoplay
              playsinline
              muted
            ></video>
            <ReferenceCardGuide
              detected={!!reference}
              confidence={reference?.confidence ?? 0}
            />
          </div>

          <div class="mt-auto space-y-3">
            <Button variant="primary" size="lg" class="w-full" onclick={capturePhoto}>
              Capture Photo
            </Button>
            <Button variant="secondary" size="md" class="w-full" onclick={stopCamera}>
              Cancel
            </Button>
          </div>
        {:else}
          <div class="flex flex-1 flex-col items-center justify-center">
            <!-- Instructions -->
            <div class="mb-8 text-center">
              <div class="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-purple-500/20 text-3xl">
                📐
              </div>
              <p class="mb-2 text-gray-300">
                Take a photo of your food with a <strong>credit card</strong> for scale
              </p>
              <p class="text-sm text-gray-500">
                The card helps estimate portion size accurately
              </p>
            </div>

            {#if cameraError}
              <div class="mb-4 text-center text-sm text-yellow-400">
                {cameraError}
              </div>
            {/if}

            <div class="w-full space-y-3">
              <Button variant="primary" size="lg" class="w-full" onclick={startCamera}>
                Open Camera
              </Button>

              <div class="flex items-center gap-3">
                <div class="h-px flex-1 bg-gray-800"></div>
                <span class="text-xs text-gray-500">or</span>
                <div class="h-px flex-1 bg-gray-800"></div>
              </div>

              <label
                class="flex w-full cursor-pointer items-center justify-center rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-gray-300 transition-colors hover:bg-gray-700"
              >
                <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                  />
                </svg>
                Choose from gallery
                <input
                  type="file"
                  accept="image/*"
                  class="hidden"
                  onchange={handleFileSelect}
                />
              </label>
            </div>
          </div>
        {/if}
      </div>

    {:else if currentStep === 'region' && imageUrl}
      <!-- Region selection step -->
      <div class="flex flex-1 flex-col">
        {#if detecting}
          <div class="flex flex-1 items-center justify-center">
            <div class="text-center">
              <div class="mx-auto mb-3 h-8 w-8 animate-spin rounded-full border-2 border-purple-500 border-t-transparent"></div>
              <p class="text-gray-400">Detecting reference card...</p>
            </div>
          </div>
        {:else}
          <!-- Reference status -->
          <div class="mb-3 rounded-lg px-3 py-2 {reference ? 'bg-green-500/10' : 'bg-yellow-500/10'}">
            {#if reference}
              <p class="text-sm text-green-400">
                {reference.type === 'credit-card' ? 'Card' : 'Coin'} detected ({Math.round(reference.confidence * 100)}% confidence)
              </p>
            {:else}
              <p class="text-sm text-yellow-400">
                No reference detected. Estimates may be less accurate.
              </p>
            {/if}
          </div>

          <FoodRegionSelector
            {imageUrl}
            {regions}
            onRegionsChange={handleRegionsChange}
          />

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

    {:else if currentStep === 'food-type'}
      <!-- Food type selection step -->
      <div class="flex flex-1 flex-col">
        <FoodTypeSelector selected={selectedFood} onSelect={handleFoodSelect} />
      </div>

    {:else if currentStep === 'result' && result}
      <!-- Result step -->
      <div class="flex flex-1 flex-col">
        <!-- Small image preview -->
        {#if imageUrl}
          <div class="mb-4 h-32 overflow-hidden rounded-lg">
            <img src={imageUrl} alt="Food" class="h-full w-full object-cover" />
          </div>
        {/if}

        <EstimationResult
          {result}
          onCarbsChange={handleCarbsChange}
          onSave={saveResult}
        />
      </div>
    {/if}
  </div>
</div>
