<script lang="ts">
  /**
   * Workstream C: Local Food Volume Estimation
   * Branch: workstream-c/local-food
   *
   * This route handles browser-local food volume estimation
   * using reference objects (credit card, coins).
   * Placeholder until workstream implementation.
   */
  import { Button } from '$lib/components/ui';
</script>

<svelte:head>
  <title>Volume Estimation - MeData</title>
</svelte:head>

<div class="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
  <div
    class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-purple-500/20 text-4xl"
  >
    📐
  </div>

  <h1 class="mb-2 text-xl font-semibold text-white">Local Volume Estimation</h1>

  <p class="mb-6 max-w-sm text-gray-400">
    Estimate portion sizes using a reference card - no cloud AI needed. All processing happens on
    your device. This feature is coming in Workstream C.
  </p>

  <div class="mb-8 rounded-lg border border-dashed border-gray-700 bg-gray-900/50 px-6 py-4">
    <p class="text-sm text-gray-500">
      Branch: <code class="text-brand-accent">workstream-c/local-food</code>
    </p>
  </div>

  <Button href="/log/meal" variant="secondary">Back to Meal Entry</Button>
</div>
