<script lang="ts">
  /**
   * Workstream B: CGM Graph Image Capture
   * Branch: workstream-b/cgm-capture
   *
   * This route handles extracting BSL data from CGM app screenshots.
   * Placeholder until workstream implementation.
   */
  import { Button } from '$lib/components/ui';
</script>

<svelte:head>
  <title>CGM Graph Import - MeData</title>
</svelte:head>

<div class="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
  <div
    class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-orange-500/20 text-4xl"
  >
    📊
  </div>

  <h1 class="mb-2 text-xl font-semibold text-white">CGM Graph Import</h1>

  <p class="mb-6 max-w-sm text-gray-400">
    Upload screenshots from Freestyle Libre, Dexcom, or other CGM apps. We'll extract the BSL
    time-series data automatically. This feature is coming in Workstream B.
  </p>

  <div class="mb-4 rounded-lg border border-gray-700 bg-gray-900/50 px-4 py-3">
    <p class="mb-2 text-sm font-medium text-gray-300">Supported formats:</p>
    <div class="flex flex-wrap justify-center gap-2 text-xs">
      <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Freestyle Libre</span>
      <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Dexcom G6/G7</span>
      <span class="rounded bg-gray-800 px-2 py-1 text-gray-400">Medtronic</span>
    </div>
  </div>

  <div class="mb-8 rounded-lg border border-dashed border-gray-700 bg-gray-900/50 px-6 py-4">
    <p class="text-sm text-gray-500">
      Branch: <code class="text-brand-accent">workstream-b/cgm-capture</code>
    </p>
  </div>

  <Button href="/import" variant="secondary">Back to Import</Button>
</div>
