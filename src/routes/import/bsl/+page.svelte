<script lang="ts">
  /**
   * Workstream D: BSL CSV Import
   * Branch: workstream-d/bsl-import
   *
   * This route handles importing BSL data from CSV files.
   * Placeholder until workstream implementation.
   */
  import { Button } from '$lib/components/ui';
</script>

<svelte:head>
  <title>CSV Import - MeData</title>
</svelte:head>

<div class="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
  <div class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-blue-500/20 text-4xl">
    📄
  </div>

  <h1 class="mb-2 text-xl font-semibold text-white">CSV Import</h1>

  <p class="mb-6 max-w-sm text-gray-400">
    Import blood sugar data from CSV exports. Supports Freestyle Libre, Dexcom Clarity, and generic
    CSV formats. This feature is coming in Workstream D.
  </p>

  <div class="mb-4 rounded-lg border border-gray-700 bg-gray-900/50 px-4 py-3">
    <p class="mb-2 text-sm font-medium text-gray-300">Supported formats:</p>
    <div class="flex flex-wrap justify-center gap-2 text-xs">
      <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Libre CSV</span>
      <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Dexcom Clarity</span>
      <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Generic CSV</span>
    </div>
  </div>

  <div class="mb-8 rounded-lg border border-dashed border-gray-700 bg-gray-900/50 px-6 py-4">
    <p class="text-sm text-gray-500">
      Branch: <code class="text-brand-accent">workstream-d/bsl-import</code>
    </p>
  </div>

  <Button href="/import" variant="secondary">Back to Import</Button>
</div>
