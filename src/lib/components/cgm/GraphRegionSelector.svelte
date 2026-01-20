<script lang="ts">
  /**
   * Graph Region Selector Component
   *
   * Allows users to manually select the graph region if auto-detection fails.
   * Draws a selection rectangle over the image.
   */
  import type { GraphRegion } from '$lib/types/cgm';

  interface Props {
    imageUrl: string;
    initialRegion?: GraphRegion;
    onRegionSelected: (region: GraphRegion) => void;
  }

  let { imageUrl, initialRegion, onRegionSelected }: Props = $props();

  let container = $state<HTMLDivElement | null>(null);
  let imageElement = $state<HTMLImageElement | null>(null);
  let isSelecting = $state(false);
  let startX = $state(0);
  let startY = $state(0);
  let currentRegion = $state<GraphRegion>({ x: 0, y: 0, width: 100, height: 100 });

  // Sync from initialRegion prop
  $effect(() => {
    if (initialRegion) {
      currentRegion = initialRegion;
    }
  });

  function getRelativePosition(event: MouseEvent | TouchEvent): { x: number; y: number } {
    if (!container) return { x: 0, y: 0 };

    const rect = container.getBoundingClientRect();
    const clientX = 'touches' in event ? event.touches[0].clientX : event.clientX;
    const clientY = 'touches' in event ? event.touches[0].clientY : event.clientY;

    return {
      x: ((clientX - rect.left) / rect.width) * 100,
      y: ((clientY - rect.top) / rect.height) * 100
    };
  }

  function handleStart(event: MouseEvent | TouchEvent) {
    event.preventDefault();
    const pos = getRelativePosition(event);
    startX = pos.x;
    startY = pos.y;
    isSelecting = true;

    currentRegion = { x: pos.x, y: pos.y, width: 0, height: 0 };
  }

  function handleMove(event: MouseEvent | TouchEvent) {
    if (!isSelecting) return;
    event.preventDefault();

    const pos = getRelativePosition(event);

    // Calculate rectangle from start to current position
    const x = Math.min(startX, pos.x);
    const y = Math.min(startY, pos.y);
    const width = Math.abs(pos.x - startX);
    const height = Math.abs(pos.y - startY);

    currentRegion = { x, y, width, height };
  }

  function handleEnd() {
    if (!isSelecting) return;
    isSelecting = false;

    // Only trigger if region is meaningful (at least 10% in each dimension)
    if (currentRegion.width >= 10 && currentRegion.height >= 10) {
      onRegionSelected(currentRegion);
    }
  }

  function resetRegion() {
    currentRegion = { x: 0, y: 0, width: 100, height: 100 };
    onRegionSelected(currentRegion);
  }
</script>

<div class="space-y-4">
  <div class="flex items-center justify-between">
    <p class="text-sm text-gray-400">
      Drag to select the graph area (optional)
    </p>
    <button
      type="button"
      class="text-sm text-brand-accent hover:underline"
      onclick={resetRegion}
    >
      Use Full Image
    </button>
  </div>

  <!-- svelte-ignore a11y_no_noninteractive_element_interactions a11y_no_noninteractive_tabindex -->
  <div
    bind:this={container}
    class="relative cursor-crosshair overflow-hidden rounded-lg touch-none"
    role="application"
    aria-label="Graph region selector"
    tabindex="0"
    onmousedown={handleStart}
    onmousemove={handleMove}
    onmouseup={handleEnd}
    onmouseleave={handleEnd}
    ontouchstart={handleStart}
    ontouchmove={handleMove}
    ontouchend={handleEnd}
  >
    <!-- Image -->
    <img
      bind:this={imageElement}
      src={imageUrl}
      alt="CGM graph screenshot"
      class="w-full select-none"
      draggable="false"
    />

    <!-- Dimmed overlay outside selection -->
    {#if currentRegion.width > 0 && currentRegion.height > 0}
      <!-- Top overlay -->
      <div
        class="pointer-events-none absolute left-0 top-0 bg-black/50"
        style="width: 100%; height: {currentRegion.y}%;"
      ></div>

      <!-- Bottom overlay -->
      <div
        class="pointer-events-none absolute bottom-0 left-0 bg-black/50"
        style="width: 100%; height: {100 - currentRegion.y - currentRegion.height}%;"
      ></div>

      <!-- Left overlay -->
      <div
        class="pointer-events-none absolute left-0 bg-black/50"
        style="top: {currentRegion.y}%; width: {currentRegion.x}%; height: {currentRegion.height}%;"
      ></div>

      <!-- Right overlay -->
      <div
        class="pointer-events-none absolute right-0 bg-black/50"
        style="top: {currentRegion.y}%; width: {100 - currentRegion.x - currentRegion.width}%; height: {currentRegion.height}%;"
      ></div>

      <!-- Selection border -->
      <div
        class="pointer-events-none absolute border-2 border-brand-accent"
        style="
          left: {currentRegion.x}%;
          top: {currentRegion.y}%;
          width: {currentRegion.width}%;
          height: {currentRegion.height}%;
        "
      >
        <!-- Corner handles -->
        <div class="absolute -left-1 -top-1 h-3 w-3 rounded-full bg-brand-accent"></div>
        <div class="absolute -right-1 -top-1 h-3 w-3 rounded-full bg-brand-accent"></div>
        <div class="absolute -bottom-1 -left-1 h-3 w-3 rounded-full bg-brand-accent"></div>
        <div class="absolute -bottom-1 -right-1 h-3 w-3 rounded-full bg-brand-accent"></div>
      </div>
    {/if}
  </div>

  {#if currentRegion.width > 0 && currentRegion.height > 0 && currentRegion.width < 100}
    <p class="text-center text-xs text-gray-500">
      Selected region: {Math.round(currentRegion.width)}% x {Math.round(currentRegion.height)}%
    </p>
  {/if}
</div>
