<script lang="ts">
  /**
   * Workstream A: AI Food Photo Recognition
   * Branch: workstream-a/food-ai
   *
   * This route handles AI-powered food recognition from photos.
   * Placeholder until workstream implementation.
   */
  import { Button } from '$lib/components/ui';
</script>

<svelte:head>
  <title>Photo Recognition - MeData</title>
</svelte:head>

<div class="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
  <div class="mb-6 flex h-20 w-20 items-center justify-center rounded-full bg-blue-500/20 text-4xl">
    📷
  </div>

  <h1 class="mb-2 text-xl font-semibold text-white">AI Photo Recognition</h1>

  <p class="mb-6 max-w-sm text-gray-400">
    Take a photo of your meal and let AI estimate the macros. This feature is coming in Workstream
    A.
  </p>

  <div class="mb-8 rounded-lg border border-dashed border-gray-700 bg-gray-900/50 px-6 py-4">
    <p class="text-sm text-gray-500">
      Branch: <code class="text-brand-accent">workstream-a/food-ai</code>
    </p>
  </div>

  <Button href="/log/meal" variant="secondary">Back to Meal Entry</Button>
</div>
