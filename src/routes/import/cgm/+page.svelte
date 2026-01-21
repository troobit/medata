<script lang="ts">
  /**
   * Workstream B: CGM Graph Image Capture
   *
   * Full workflow for extracting BSL data from CGM app screenshots:
   * 1. Image upload/capture
   * 2. Optional region selection
   * 3. ML-assisted extraction
   * 4. Preview and axis adjustment
   * 5. Data confirmation and import
   */
  import { goto } from '$app/navigation';
  import { Button, LoadingSpinner } from '$lib/components/ui';
  import {
    CGMImageCapture,
    AxisRangeInput,
    ExtractionPreview,
    TimeSeriesConfirm
  } from '$lib/components/cgm';
  import { createCGMImageProcessor } from '$lib/services/cgm';
  import { settingsStore, eventsStore } from '$lib/stores';
  import type { CGMExtractionResult, AxisRanges, ExtractedDataPoint } from '$lib/types/cgm';

  // Workflow steps
  type Step = 'upload' | 'region' | 'extracting' | 'preview' | 'confirm' | 'importing' | 'complete';

  let step = $state<Step>('upload');
  let imageFile = $state<File | null>(null);
  let imageUrl = $state<string | null>(null);
  let extractionResult = $state<CGMExtractionResult | null>(null);
  let error = $state<string | null>(null);

  // Check if ML is configured
  const isConfigured = $derived(settingsStore.isAIConfigured);

  function handleImageSelected(file: File, previewUrl: string) {
    imageFile = file;
    imageUrl = previewUrl;
    error = null;

    // Skip region selection for now - go directly to extraction
    // Users can adjust axis ranges after extraction
    startExtraction();
  }

  async function startExtraction() {
    if (!imageFile) return;

    step = 'extracting';
    error = null;

    try {
      const processor = createCGMImageProcessor(settingsStore.settings);

      if (!processor.isConfigured()) {
        throw new Error('No ML provider configured. Please set up an API key in Settings.');
      }

      extractionResult = await processor.extractFromImage(imageFile);

      step = 'preview';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to extract data from image';
      step = 'upload';
    }
  }

  function handleAxisRangesChanged(newRanges: AxisRanges) {
    if (!extractionResult) return;

    // Update the extraction result with new axis ranges
    // This will recalculate the data point timestamps
    extractionResult = {
      ...extractionResult,
      axisRanges: newRanges
    };
  }

  function proceedToConfirm() {
    step = 'confirm';
  }

  async function handleConfirm(points: ExtractedDataPoint[]) {
    step = 'importing';
    error = null;

    try {
      // Import all data points as BSL events
      const unit = extractionResult?.axisRanges.unit || 'mmol/L';
      const device = extractionResult?.deviceType || 'generic';

      for (const point of points) {
        await eventsStore.logBSL(point.value, unit, point.timestamp, {
          source: 'cgm-image',
          device:
            device === 'freestyle-libre'
              ? 'Freestyle Libre'
              : device === 'dexcom'
                ? 'Dexcom'
                : device === 'medtronic'
                  ? 'Medtronic'
                  : 'CGM'
        });
      }

      step = 'complete';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to import data';
      step = 'confirm';
    }
  }

  function handleCancel() {
    if (step === 'confirm') {
      step = 'preview';
    } else {
      reset();
    }
  }

  function reset() {
    step = 'upload';
    imageFile = null;
    if (imageUrl) {
      URL.revokeObjectURL(imageUrl);
    }
    imageUrl = null;
    extractionResult = null;
    error = null;
  }

  function goToHistory() {
    goto('/history');
  }
</script>

<svelte:head>
  <title>CGM Graph Import - MeData</title>
</svelte:head>

<div class="min-h-[calc(100dvh-80px)] px-4 py-6">
  <header class="mb-6">
    <a href="/import" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
      <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back
    </a>
    <h1 class="text-2xl font-bold text-white">CGM Graph Import</h1>
    <p class="mt-1 text-sm text-gray-400">Extract BSL data from CGM app screenshots</p>
  </header>

  <!-- Progress indicator -->
  {#if step !== 'upload' && step !== 'complete'}
    <div class="mb-6 flex items-center justify-center gap-2">
      {#each ['upload', 'extracting', 'preview', 'confirm'] as s, i}
        <div
          class="h-2 w-2 rounded-full {['upload', 'extracting', 'preview', 'confirm'].indexOf(
            step
          ) >= i
            ? 'bg-brand-accent'
            : 'bg-gray-700'}"
        ></div>
      {/each}
    </div>
  {/if}

  <!-- Error display -->
  {#if error}
    <div class="mb-6 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
      <p class="font-medium">Error</p>
      <p class="text-sm">{error}</p>
    </div>
  {/if}

  <!-- Step: Upload -->
  {#if step === 'upload'}
    {#if !isConfigured}
      <div class="mb-6 rounded-lg border border-yellow-500/50 bg-yellow-500/10 px-4 py-3">
        <p class="mb-2 font-medium text-yellow-400">ML Provider Required</p>
        <p class="mb-3 text-sm text-yellow-300/80">
          CGM graph extraction requires a cloud ML provider (OpenAI, Claude, Gemini, or Ollama).
        </p>
        <Button href="/settings" variant="secondary" size="sm">Configure in Settings</Button>
      </div>
    {/if}

    <CGMImageCapture onImageSelected={handleImageSelected} disabled={!isConfigured} />

    <div class="mt-6 rounded-lg border border-gray-700 bg-gray-900/50 px-4 py-3">
      <p class="mb-2 text-sm font-medium text-gray-300">Supported formats:</p>
      <div class="flex flex-wrap gap-2 text-xs">
        <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Freestyle Libre</span>
        <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Dexcom G6/G7</span>
        <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Medtronic</span>
        <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Generic CGM</span>
      </div>
    </div>
  {/if}

  <!-- Step: Extracting -->
  {#if step === 'extracting'}
    <div class="flex flex-col items-center justify-center py-12">
      <LoadingSpinner />
      <p class="mt-4 text-lg font-medium text-white">Extracting BSL Data...</p>
      <p class="mt-2 text-sm text-gray-400">
        Analyzing graph with {settingsStore.configuredProvider || 'ML'}
      </p>
    </div>
  {/if}

  <!-- Step: Preview -->
  {#if step === 'preview' && extractionResult && imageUrl}
    <div class="space-y-6">
      <ExtractionPreview {imageUrl} {extractionResult} />

      <AxisRangeInput
        ranges={extractionResult.axisRanges}
        onRangesChanged={handleAxisRangesChanged}
      />

      <div class="flex gap-3">
        <Button variant="secondary" class="flex-1" onclick={reset}>Start Over</Button>
        <Button variant="primary" class="flex-1" onclick={proceedToConfirm}>
          Review Data Points
        </Button>
      </div>
    </div>
  {/if}

  <!-- Step: Confirm -->
  {#if step === 'confirm' && extractionResult}
    <TimeSeriesConfirm
      dataPoints={extractionResult.dataPoints}
      axisRanges={extractionResult.axisRanges}
      onConfirm={handleConfirm}
      onCancel={handleCancel}
    />
  {/if}

  <!-- Step: Importing -->
  {#if step === 'importing'}
    <div class="flex flex-col items-center justify-center py-12">
      <LoadingSpinner />
      <p class="mt-4 text-lg font-medium text-white">Importing Data...</p>
      <p class="mt-2 text-sm text-gray-400">
        Saving {extractionResult?.dataPoints.length || 0} BSL readings
      </p>
    </div>
  {/if}

  <!-- Step: Complete -->
  {#if step === 'complete'}
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div
        class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-green-500/20 text-4xl"
      >
        <svg class="h-10 w-10 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 13l4 4L19 7"
          />
        </svg>
      </div>

      <h2 class="mb-2 text-xl font-semibold text-white">Import Complete!</h2>
      <p class="mb-6 text-gray-400">
        Successfully imported {extractionResult?.dataPoints.length || 0} BSL readings.
      </p>

      <div class="flex gap-3">
        <Button variant="secondary" onclick={reset}>Import Another</Button>
        <Button variant="primary" onclick={goToHistory}>View History</Button>
      </div>
    </div>
  {/if}
</div>
