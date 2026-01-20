<script lang="ts">
  /**
   * Photo Preview Component
   * Workstream A: AI-Powered Food Recognition
   *
   * Shows captured photo with options to retake or proceed.
   */
  import { blobToDataUrl } from '$lib/utils/imageProcessing';

  interface Props {
    image: Blob;
    onConfirm: () => void;
    onRetake: () => void;
    processing?: boolean;
  }

  let { image, onConfirm, onRetake, processing = false }: Props = $props();

  let imageUrl = $state<string | null>(null);

  $effect(() => {
    blobToDataUrl(image).then((url) => {
      imageUrl = url;
    });

    return () => {
      imageUrl = null;
    };
  });
</script>

<div class="flex flex-col">
  {#if imageUrl}
    <div class="relative mb-4 overflow-hidden rounded-lg">
      <img src={imageUrl} alt="Captured food" class="h-64 w-full object-cover" />

      {#if processing}
        <div
          class="absolute inset-0 flex items-center justify-center bg-black/50"
        >
          <div class="flex flex-col items-center">
            <div
              class="mb-2 h-8 w-8 animate-spin rounded-full border-2 border-blue-400 border-t-transparent"
            ></div>
            <span class="text-sm text-white">Analyzing...</span>
          </div>
        </div>
      {/if}
    </div>
  {:else}
    <div class="mb-4 flex h-64 items-center justify-center rounded-lg bg-gray-800">
      <div class="h-8 w-8 animate-spin rounded-full border-2 border-gray-400 border-t-transparent"></div>
    </div>
  {/if}

  <div class="grid grid-cols-2 gap-3">
    <button
      type="button"
      onclick={onRetake}
      disabled={processing}
      class="rounded-lg bg-gray-700 py-3 text-center font-medium text-white transition-colors hover:bg-gray-600 disabled:opacity-50"
    >
      Retake
    </button>

    <button
      type="button"
      onclick={onConfirm}
      disabled={processing}
      class="rounded-lg bg-blue-600 py-3 text-center font-medium text-white transition-colors hover:bg-blue-500 disabled:opacity-50"
    >
      {processing ? 'Analyzing...' : 'Analyze'}
    </button>
  </div>
</div>
