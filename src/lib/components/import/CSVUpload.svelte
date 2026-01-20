<script lang="ts">
  /**
   * Workstream D: CSV Upload Component
   * Branch: dev-4
   *
   * Drag-and-drop file upload for CSV files.
   */
  import type { CSVFormatType } from '$lib/types';

  interface Props {
    onFileSelect: (file: File, format: CSVFormatType) => void;
    detectFormat: (file: File) => Promise<CSVFormatType>;
    disabled?: boolean;
  }

  let { onFileSelect, detectFormat, disabled = false }: Props = $props();

  let isDragging = $state(false);
  let isDetecting = $state(false);
  let error = $state<string | null>(null);
  let selectedFile = $state<File | null>(null);
  let detectedFormat = $state<CSVFormatType | null>(null);

  function handleDragOver(e: DragEvent) {
    e.preventDefault();
    if (!disabled) isDragging = true;
  }

  function handleDragLeave(e: DragEvent) {
    e.preventDefault();
    isDragging = false;
  }

  async function handleDrop(e: DragEvent) {
    e.preventDefault();
    isDragging = false;
    if (disabled) return;

    const files = e.dataTransfer?.files;
    if (files && files.length > 0) {
      await processFile(files[0]);
    }
  }

  async function handleFileInput(e: Event) {
    const input = e.target as HTMLInputElement;
    const files = input.files;
    if (files && files.length > 0) {
      await processFile(files[0]);
    }
  }

  async function processFile(file: File) {
    error = null;

    // Validate file type
    if (!file.name.endsWith('.csv') && !file.type.includes('csv')) {
      error = 'Please select a CSV file';
      return;
    }

    // Validate file size (max 10MB)
    if (file.size > 10 * 1024 * 1024) {
      error = 'File is too large (max 10MB)';
      return;
    }

    selectedFile = file;
    isDetecting = true;

    try {
      const format = await detectFormat(file);
      detectedFormat = format;
      onFileSelect(file, format);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to process file';
      selectedFile = null;
      detectedFormat = null;
    } finally {
      isDetecting = false;
    }
  }

  function clearFile() {
    selectedFile = null;
    detectedFormat = null;
    error = null;
  }

  const formatLabels: Record<CSVFormatType, string> = {
    'freestyle-libre': 'Freestyle Libre',
    dexcom: 'Dexcom Clarity',
    generic: 'Generic CSV'
  };
</script>

<div class="space-y-4">
  <!-- Drop Zone -->
  <div
    role="button"
    tabindex="0"
    class="relative rounded-lg border-2 border-dashed transition-colors {isDragging
      ? 'border-brand-accent bg-brand-accent/10'
      : 'border-gray-700 hover:border-gray-600'} {disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}"
    ondragover={handleDragOver}
    ondragleave={handleDragLeave}
    ondrop={handleDrop}
    onkeydown={(e) => e.key === 'Enter' && document.getElementById('csv-file-input')?.click()}
  >
    <input
      id="csv-file-input"
      type="file"
      accept=".csv,text/csv"
      class="absolute inset-0 h-full w-full cursor-pointer opacity-0"
      onchange={handleFileInput}
      {disabled}
    />

    <div class="flex flex-col items-center justify-center px-6 py-10 text-center">
      {#if isDetecting}
        <div class="mb-4 h-12 w-12 animate-spin rounded-full border-4 border-gray-600 border-t-brand-accent"></div>
        <p class="text-gray-300">Detecting format...</p>
      {:else if selectedFile}
        <div class="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-green-500/20 text-2xl">
          ✓
        </div>
        <p class="font-medium text-white">{selectedFile.name}</p>
        <p class="mt-1 text-sm text-gray-400">
          {(selectedFile.size / 1024).toFixed(1)} KB
          {#if detectedFormat}
            • {formatLabels[detectedFormat]}
          {/if}
        </p>
        <button
          type="button"
          class="mt-3 text-sm text-gray-400 underline hover:text-white"
          onclick={clearFile}
        >
          Choose different file
        </button>
      {:else}
        <svg class="mb-4 h-12 w-12 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
          />
        </svg>
        <p class="text-gray-300">
          <span class="font-medium text-white">Drop CSV file here</span> or click to browse
        </p>
        <p class="mt-2 text-sm text-gray-500">
          Supports Freestyle Libre, Dexcom Clarity, and generic CSV
        </p>
      {/if}
    </div>
  </div>

  <!-- Error Message -->
  {#if error}
    <div class="rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
      {error}
    </div>
  {/if}
</div>
