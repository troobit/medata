<script lang="ts">
  /**
   * AI Food Photo Recognition Page
   * Workstream A: AI-Powered Food Recognition
   *
   * Full flow: Capture -> Preview -> Analyze -> Edit -> Save
   */
  import { goto } from '$app/navigation';
  import { CameraCapture, PhotoPreview, FoodRecognitionResult } from '$lib/components/ai';
  import { RecogniseFoodWithFallback } from '$lib/services/ai';
  import { compressImage, blobToDataUrl } from '$lib/utils/imageProcessing';
  import { settingsStore, eventsStore } from '$lib/stores';
  import type {
    FoodRecognitionResult as FoodRecognitionResultType,
    RecognisedFoodItem
  } from '$lib/types/ai';
  import type { MacroData } from '$lib/types/events';
  import { Button } from '$lib/components/ui';

  type FlowState = 'capture' | 'preview' | 'result';

  let flowState = $state<FlowState>('capture');
  let capturedImage = $state<Blob | null>(null);
  let imageUrl = $state<string | null>(null);
  let recognitionResult = $state<FoodRecognitionResultType | null>(null);
  let processing = $state(false);
  let saving = $state(false);
  let error = $state<string | null>(null);

  // Check if AI is configured
  let aiConfigured = $derived(settingsStore.isAIConfigured);

  async function handleCapture(blob: Blob) {
    error = null;
    try {
      // Compress the image for faster upload
      capturedImage = await compressImage(blob, {
        maxWidth: 1024,
        maxHeight: 1024,
        quality: 0.85,
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
    error = null;
    flowState = 'capture';
  }

  async function handleAnalyze() {
    if (!capturedImage) return;

    error = null;
    processing = true;

    try {
      recognitionResult = await RecogniseFoodWithFallback(capturedImage, settingsStore.settings);
      flowState = 'result';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Recognition failed';
    } finally {
      processing = false;
    }
  }

  async function handleSave(macros: MacroData, items: RecognisedFoodItem[]) {
    saving = true;
    error = null;

    try {
      await eventsStore.logMeal(macros.carbs, {
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
</script>

<svelte:head>
  <title>Photo Recognition - MeData</title>
</svelte:head>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-6">
    <a href="/log/meal" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
      <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back
    </a>
    <h1 class="text-2xl font-bold text-white">AI Photo Recognition</h1>
    <p class="mt-1 text-sm text-gray-400">
      {#if flowState === 'capture'}
        Take a photo of your meal
      {:else if flowState === 'preview'}
        Review your photo
      {:else}
        Review and adjust the results
      {/if}
    </p>
  </header>

  {#if !aiConfigured}
    <!-- No AI Configured -->
    <div class="flex flex-1 flex-col items-center justify-center text-center">
      <div
        class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-yellow-500/20 text-4xl"
      >
        ⚙️
      </div>
      <h2 class="mb-2 text-xl font-semibold text-white">AI Not Configured</h2>
      <p class="mb-6 max-w-sm text-gray-400">
        To use AI food recognition, please add an API key in Settings.
      </p>
      <div class="flex gap-3">
        <Button href="/settings" variant="primary">Go to Settings</Button>
        <Button href="/log/meal" variant="secondary">Manual Entry</Button>
      </div>
    </div>
  {:else}
    <!-- Main Flow -->
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
          onConfirm={handleAnalyze}
          onRetake={handleRetake}
          {processing}
        />
      {:else if flowState === 'result' && recognitionResult}
        <FoodRecognitionResult
          result={recognitionResult}
          imageUrl={imageUrl ?? undefined}
          onSave={handleSave}
          onCancel={handleRetake}
          {saving}
        />
      {/if}
    </div>
  {/if}
</div>
