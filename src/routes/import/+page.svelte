<script lang="ts">
  /**
   * Import Hub
   *
   * Entry point for data import features.
   * Links to workstream-specific import routes.
   */
  import { Button } from '$lib/components/ui';
</script>

<svelte:head>
  <title>Import Data - MeData</title>
</svelte:head>

<div class="px-4 py-6">
  <h1 class="mb-6 text-2xl font-bold text-white">Import Data</h1>

  <div class="space-y-4">
    <!-- CGM Graph Import - Workstream B -->
    <a
      href="/import/cgm"
      class="flex items-center gap-4 rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
    >
      <div
        class="flex h-12 w-12 items-center justify-center rounded-full bg-orange-500/20 text-2xl"
      >
        📊
      </div>
      <div class="flex-1">
        <h2 class="font-semibold text-white">CGM Graph Screenshots</h2>
        <p class="text-sm text-gray-400">Extract data from Libre/Dexcom app screenshots</p>
      </div>
      <span class="text-gray-500">→</span>
    </a>

    <!-- CSV Import - Workstream D -->
    <a
      href="/import/bsl"
      class="flex items-center gap-4 rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
    >
      <div class="flex h-12 w-12 items-center justify-center rounded-full bg-blue-500/20 text-2xl">
        📄
      </div>
      <div class="flex-1">
        <h2 class="font-semibold text-white">CSV Import</h2>
        <p class="text-sm text-gray-400">Import BSL data from Libre/Dexcom CSV exports</p>
      </div>
      <span class="text-gray-500">→</span>
    </a>
  </div>

  <div class="mt-8">
    <Button href="/" variant="secondary" class="w-full">Back to Home</Button>
  </div>
</div>
