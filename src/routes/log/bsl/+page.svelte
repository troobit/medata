<script lang="ts">
  /**
   * Workstream D: Manual BSL Entry
   * Branch: workstream-d/bsl-import
   *
   * This route handles manual blood sugar level entry.
   * Placeholder until workstream implementation.
   */
  import { Button } from '$lib/components/ui';
</script>

<svelte:head>
  <title>Log BSL - MeData</title>
</svelte:head>

<div class="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
  <div
    class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-yellow-500/20 text-4xl"
  >
    🩸
  </div>

  <h1 class="mb-2 text-xl font-semibold text-white">Log Blood Sugar</h1>

  <p class="mb-6 max-w-sm text-gray-400">
    Manually enter blood sugar readings from finger pricks or CGM. Finger prick readings are marked
    as higher accuracy. This feature is coming in Workstream D.
  </p>

  <div class="mb-8 rounded-lg border border-dashed border-gray-700 bg-gray-900/50 px-6 py-4">
    <p class="text-sm text-gray-500">
      Branch: <code class="text-brand-accent">workstream-d/bsl-import</code>
    </p>
  </div>

  <Button href="/log" variant="secondary">Back to Log</Button>
</div>
