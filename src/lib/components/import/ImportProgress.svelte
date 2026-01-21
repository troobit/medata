<script lang="ts">
  /**
   * Workstream D: Import Progress Component
   * Branch: dev-4
   *
   * Shows progress during CSV import.
   */
  import type { ImportResult } from '$lib/types';

  interface Props {
    isImporting: boolean;
    result?: ImportResult | null;
    error?: string | null;
  }

  let { isImporting, result = null, error = null }: Props = $props();
</script>

<div class="space-y-6">
  {#if isImporting}
    <!-- Loading State -->
    <div class="flex flex-col items-center justify-center py-12">
      <div
        class="mb-6 h-16 w-16 animate-spin rounded-full border-4 border-gray-600 border-t-brand-accent"
      ></div>
      <p class="text-lg font-medium text-white">Importing data...</p>
      <p class="mt-2 text-gray-400">This may take a moment for large files</p>
    </div>
  {:else if error}
    <!-- Error State -->
    <div class="flex flex-col items-center justify-center py-12">
      <div
        class="mb-6 flex h-16 w-16 items-center justify-center rounded-full bg-red-500/20 text-4xl"
      >
        ✕
      </div>
      <p class="text-lg font-medium text-red-400">Import failed</p>
      <p class="mt-2 max-w-md text-center text-gray-400">{error}</p>
    </div>
  {:else if result}
    <!-- Success State -->
    <div class="flex flex-col items-center justify-center py-12">
      <div
        class="mb-6 flex h-16 w-16 items-center justify-center rounded-full bg-green-500/20 text-4xl"
      >
        ✓
      </div>
      <p class="text-lg font-medium text-green-400">Import complete!</p>

      <!-- Result Stats -->
      <div class="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div class="rounded-lg bg-gray-800 p-4 text-center">
          <p class="text-2xl font-bold text-green-400">{result.imported}</p>
          <p class="text-sm text-gray-400">Imported</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4 text-center">
          <p class="text-2xl font-bold text-yellow-400">{result.skipped}</p>
          <p class="text-sm text-gray-400">Skipped</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4 text-center">
          <p class="text-2xl font-bold text-red-400">{result.failed}</p>
          <p class="text-sm text-gray-400">Failed</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4 text-center">
          <p class="text-2xl font-bold text-gray-400">{result.duplicatesHandled}</p>
          <p class="text-sm text-gray-400">Duplicates</p>
        </div>
      </div>
    </div>
  {/if}
</div>
