<script lang="ts">
  /**
   * Workstream D: BSL CSV Import Wizard
   * Branch: dev-4
   *
   * Multi-step wizard for importing BSL data from CSV files.
   */
  import { Button } from '$lib/components/ui';
  import {
    CSVUpload,
    ImportPreview,
    DuplicateResolver,
    ImportProgress,
    ColumnMapper
  } from '$lib/components/import';
  import { getCSVParser, getAvailableColumns, suggestColumnMapping } from '$lib/services/import';
  import { eventsStore, settingsStore } from '$lib/stores';
  import type {
    CSVFormatType,
    ImportPreview as ImportPreviewType,
    ImportResult,
    DuplicateStrategy,
    CSVColumnMapping,
    BSLUnit
  } from '$lib/types';

  // Wizard steps
  type Step = 'upload' | 'mapping' | 'preview' | 'duplicates' | 'importing' | 'complete';

  let step = $state<Step>('upload');
  let selectedFile = $state<File | null>(null);
  let detectedFormat = $state<CSVFormatType | null>(null);
  let availableColumns = $state<string[]>([]);
  let columnMapping = $state<CSVColumnMapping | null>(null);
  let mappingUnit = $state<BSLUnit>('mmol/L');
  let preview = $state<ImportPreviewType | null>(null);
  let duplicateStrategy = $state<DuplicateStrategy>('skip');
  let importResult = $state<ImportResult | null>(null);
  let error = $state<string | null>(null);
  let isLoading = $state(false);

  const parser = getCSVParser();

  async function handleFileSelect(file: File, format: CSVFormatType) {
    selectedFile = file;
    detectedFormat = format;
    error = null;

    // For generic format, need column mapping first
    if (format === 'generic') {
      isLoading = true;
      try {
        availableColumns = await getAvailableColumns(file);
        const suggested = await suggestColumnMapping(file);
        if (suggested) {
          columnMapping = suggested;
        }
        step = 'mapping';
      } catch (e) {
        error = e instanceof Error ? e.message : 'Failed to read file';
      } finally {
        isLoading = false;
      }
    } else {
      // Auto-detected format, go straight to parsing
      await parseFile(file, format);
    }
  }

  function handleMappingChange(mapping: CSVColumnMapping, unit: BSLUnit) {
    columnMapping = mapping;
    mappingUnit = unit;
  }

  async function confirmMapping() {
    if (!selectedFile || !columnMapping) return;
    await parseFile(selectedFile, 'generic', columnMapping, mappingUnit);
  }

  async function parseFile(
    file: File,
    format: CSVFormatType,
    mapping?: CSVColumnMapping,
    unit?: BSLUnit
  ) {
    isLoading = true;
    error = null;

    try {
      preview = await parser.parseCSV(file, {
        format,
        columnMapping: mapping,
        defaultUnit: unit
      });

      // Decide next step based on duplicates
      if (preview.duplicates.length > 0) {
        step = 'duplicates';
      } else {
        step = 'preview';
      }
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to parse file';
      step = 'upload';
    } finally {
      isLoading = false;
    }
  }

  function handleStrategyChange(strategy: DuplicateStrategy) {
    duplicateStrategy = strategy;
  }

  async function startImport() {
    if (!preview) return;

    step = 'importing';
    error = null;

    try {
      importResult = await parser.commitImport(preview, duplicateStrategy);
      step = 'complete';
      // Refresh events store
      await eventsStore.loadRecent();
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to import data';
      step = 'preview';
    }
  }

  function reset() {
    step = 'upload';
    selectedFile = null;
    detectedFormat = null;
    availableColumns = [];
    columnMapping = null;
    preview = null;
    importResult = null;
    error = null;
  }

  function goBack() {
    switch (step) {
      case 'mapping':
        step = 'upload';
        break;
      case 'preview':
        if (detectedFormat === 'generic') {
          step = 'mapping';
        } else {
          step = 'upload';
        }
        break;
      case 'duplicates':
        step = 'preview';
        break;
      default:
        break;
    }
  }

  // Step titles
  const stepTitles: Record<Step, string> = {
    upload: 'Select CSV File',
    mapping: 'Map Columns',
    preview: 'Review Data',
    duplicates: 'Handle Duplicates',
    importing: 'Importing...',
    complete: 'Import Complete'
  };
</script>

<svelte:head>
  <title>CSV Import - MeData</title>
</svelte:head>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-8">
    {#if step !== 'upload' && step !== 'importing' && step !== 'complete'}
      <button
        type="button"
        class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200"
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
    {:else if step === 'upload'}
      <a href="/import" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
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
    {/if}
    <h1 class="text-2xl font-bold text-white">{stepTitles[step]}</h1>
  </header>

  <div class="flex flex-1 flex-col">
    <!-- Step: Upload -->
    {#if step === 'upload'}
      <CSVUpload
        onFileSelect={handleFileSelect}
        detectFormat={(file) => parser.detectFormat(file)}
        disabled={isLoading}
      />

      {#if isLoading}
        <div class="mt-6 flex items-center justify-center gap-3 text-gray-400">
          <div
            class="h-5 w-5 animate-spin rounded-full border-2 border-gray-600 border-t-brand-accent"
          ></div>
          Processing file...
        </div>
      {/if}
    {/if}

    <!-- Step: Column Mapping (for generic CSV) -->
    {#if step === 'mapping'}
      <ColumnMapper
        columns={availableColumns}
        suggestedMapping={columnMapping}
        onMappingChange={handleMappingChange}
      />

      <div class="mt-8">
        <Button
          variant="primary"
          size="lg"
          class="w-full"
          onclick={confirmMapping}
          disabled={!columnMapping?.timestampColumn || !columnMapping?.valueColumn || isLoading}
          loading={isLoading}
        >
          Continue
        </Button>
      </div>
    {/if}

    <!-- Step: Preview -->
    {#if step === 'preview' && preview}
      <ImportPreview {preview} displayUnit={settingsStore.settings.defaultBSLUnit} />

      <div class="mt-8 space-y-3">
        {#if preview.duplicates.length > 0}
          <Button
            variant="secondary"
            size="lg"
            class="w-full"
            onclick={() => (step = 'duplicates')}
          >
            Review {preview.duplicates.length} Duplicate{preview.duplicates.length !== 1 ? 's' : ''}
          </Button>
        {/if}

        <Button
          variant="primary"
          size="lg"
          class="w-full"
          onclick={startImport}
          disabled={preview.validRows.length === 0}
        >
          Import {preview.validRows.length} Reading{preview.validRows.length !== 1 ? 's' : ''}
        </Button>
      </div>
    {/if}

    <!-- Step: Duplicates -->
    {#if step === 'duplicates' && preview}
      <DuplicateResolver
        duplicates={preview.duplicates}
        selectedStrategy={duplicateStrategy}
        onStrategyChange={handleStrategyChange}
      />

      <div class="mt-8">
        <Button variant="primary" size="lg" class="w-full" onclick={() => (step = 'preview')}>
          Continue to Import
        </Button>
      </div>
    {/if}

    <!-- Step: Importing / Complete -->
    {#if step === 'importing' || step === 'complete'}
      <ImportProgress isImporting={step === 'importing'} result={importResult} {error} />

      {#if step === 'complete'}
        <div class="mt-8 space-y-3">
          <Button variant="primary" size="lg" class="w-full" href="/">Done</Button>
          <Button variant="secondary" size="lg" class="w-full" onclick={reset}>
            Import Another File
          </Button>
        </div>
      {/if}
    {/if}

    <!-- Error Display -->
    {#if error && step !== 'importing' && step !== 'complete'}
      <div class="mt-6 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
        {error}
      </div>
    {/if}
  </div>
</div>
