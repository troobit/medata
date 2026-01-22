<script lang="ts">
  import { goto } from '$app/navigation';
  import { Button } from '$lib/components/ui';
  import ImagePreview from '$lib/components/bsl/ImagePreview.svelte';
  import ExtractedDataEditor from '$lib/components/bsl/ExtractedDataEditor.svelte';
  import { eventsStore } from '$lib/stores';
  import { getBSLRecognitionService } from '$lib/services/BSLRecognitionService';
  import type { ExtractedBSLReading } from '$lib/types/vision';

  type PageState = 'idle' | 'loading' | 'reviewing' | 'importing' | 'success' | 'error';

  interface EditableReading extends ExtractedBSLReading {
    included: boolean;
  }

  let pageState: PageState = $state('idle');
  let errorMessage = $state('');
  let readings: ExtractedBSLReading[] = $state([]);
  let editableReadings: EditableReading[] = $state([]);
  let importedCount = $state(0);
  let detectedSource: string | undefined = $state(undefined);

  const bslService = getBSLRecognitionService();

  // Check if service is configured
  const isConfigured = $derived(bslService.isConfigured());

  // Derived value for selected readings count
  const selectedCount = $derived(
    editableReadings.filter((r: EditableReading) => r.included).length
  );

  async function handleImageSelect(base64: string) {
    if (!isConfigured) {
      pageState = 'error';
      errorMessage =
        'OpenAI API key not configured. Please set VITE_OPENAI_API_KEY in your .env file.';
      return;
    }

    pageState = 'loading';
    errorMessage = '';

    try {
      const result = await bslService.extractReadings(base64);

      if (result.error) {
        pageState = 'error';
        errorMessage = result.error;
        return;
      }

      if (result.readings.length === 0) {
        pageState = 'error';
        errorMessage =
          'No blood sugar readings found in the image. Please try a different screenshot.';
        return;
      }

      readings = result.readings;
      detectedSource = result.imageMetadata?.source;
      pageState = 'reviewing';
    } catch (err) {
      pageState = 'error';
      errorMessage = err instanceof Error ? err.message : 'Failed to analyse image';
    }
  }

  function handleReadingsChange(updated: EditableReading[]) {
    editableReadings = updated;
  }

  async function handleImport() {
    const toImport = editableReadings.filter((r: EditableReading) => r.included);

    if (toImport.length === 0) {
      errorMessage = 'Please select at least one reading to import';
      return;
    }

    pageState = 'importing';
    errorMessage = '';

    try {
      await eventsStore.bulkLogBSL(
        toImport.map((r: EditableReading) => ({
          value: r.value,
          unit: r.unit,
          timestamp: r.timestamp,
          source: 'cgm-image' as const
        }))
      );

      importedCount = toImport.length;
      pageState = 'success';

      // Redirect after short delay
      setTimeout(() => {
        goto('/history');
      }, 1500);
    } catch (err) {
      pageState = 'error';
      errorMessage = err instanceof Error ? err.message : 'Failed to import readings';
    }
  }

  function reset() {
    pageState = 'idle';
    errorMessage = '';
    readings = [];
    editableReadings = [];
    detectedSource = undefined;
  }

  function getSourceLabel(source: string | undefined): string {
    switch (source) {
      case 'libre':
        return 'Freestyle Libre';
      case 'dexcom':
        return 'Dexcom';
      case 'medtronic':
        return 'Medtronic';
      case 'omnipod':
        return 'Omnipod';
      default:
        return 'CGM';
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
    <h1 class="text-2xl font-bold text-white">Import from Screenshot</h1>
    <p class="mt-1 text-gray-400">Upload a CGM app screenshot to extract readings</p>
  </header>

  <div class="flex flex-1 flex-col">
    {#if pageState === 'idle'}
      {#if !isConfigured}
        <div class="mb-4 rounded-lg bg-yellow-500/20 px-4 py-3 text-yellow-400">
          <p class="font-medium">API Key Required</p>
          <p class="mt-1 text-sm">
            Set <code class="rounded bg-gray-800 px-1">VITE_OPENAI_API_KEY</code> in your .env file to
            enable image analysis.
          </p>
        </div>
      {/if}
      <ImagePreview onImageSelect={handleImageSelect} class="flex-1" />
    {:else if pageState === 'loading'}
      <div class="flex flex-1 flex-col items-center justify-center">
        <div
          class="h-12 w-12 animate-spin rounded-full border-4 border-gray-700 border-t-brand-accent"
        ></div>
        <p class="mt-4 text-gray-400">Analyzing screenshot...</p>
        <p class="mt-1 text-sm text-gray-500">This may take a few seconds</p>
      </div>
    {:else if pageState === 'reviewing'}
      <div class="mb-4">
        {#if detectedSource}
          <div class="mb-4 rounded-lg bg-gray-800 px-4 py-3">
            <span class="text-gray-400">Detected: </span>
            <span class="font-medium text-white">{getSourceLabel(detectedSource)}</span>
          </div>
        {/if}
        <ExtractedDataEditor {readings} onReadingsChange={handleReadingsChange} class="mb-6" />
      </div>

      <div class="mt-auto space-y-3">
        <Button
          variant="primary"
          size="lg"
          class="w-full"
          onclick={handleImport}
          disabled={selectedCount === 0}
        >
          Import {selectedCount} Reading{selectedCount !== 1 ? 's' : ''}
        </Button>
        <Button variant="ghost" size="md" class="w-full" onclick={reset}>Start Over</Button>
      </div>
    {:else if pageState === 'importing'}
      <div class="flex flex-1 flex-col items-center justify-center">
        <div
          class="h-12 w-12 animate-spin rounded-full border-4 border-gray-700 border-t-brand-accent"
        ></div>
        <p class="mt-4 text-gray-400">Importing readings...</p>
      </div>
    {:else if pageState === 'success'}
      <div class="flex flex-1 flex-col items-center justify-center text-center">
        <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-500/20">
          <svg class="h-8 w-8 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M5 13l4 4L19 7"
            />
          </svg>
        </div>
        <h2 class="text-xl font-bold text-white">Import Complete</h2>
        <p class="mt-2 text-gray-400">
          {importedCount} reading{importedCount !== 1 ? 's' : ''} imported successfully
        </p>
        <p class="mt-1 text-sm text-gray-500">Redirecting to history...</p>
      </div>
    {:else if pageState === 'error'}
      <div class="flex flex-1 flex-col items-center justify-center text-center">
        <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-red-500/20">
          <svg class="h-8 w-8 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </div>
        <h2 class="text-xl font-bold text-white">Something went wrong</h2>
        <p class="mt-2 text-gray-400">{errorMessage}</p>
        <Button variant="primary" size="md" class="mt-6" onclick={reset}>Try Again</Button>
      </div>
    {/if}
  </div>
</div>
