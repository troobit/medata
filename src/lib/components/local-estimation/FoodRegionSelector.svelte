<script lang="ts">
  /**
   * FoodRegionSelector - Touch/click to draw food region boundaries.
   * Allows users to outline food areas on an image.
   */
  import type { FoodRegion } from '$lib/types/local-estimation';

  interface Props {
    imageUrl: string;
    regions?: FoodRegion[];
    onRegionComplete?: (region: FoodRegion) => void;
    onRegionsChange?: (regions: FoodRegion[]) => void;
    editable?: boolean;
  }

  let {
    imageUrl,
    regions = [],
    onRegionComplete,
    onRegionsChange,
    editable = true
  }: Props = $props();

  let containerRef: HTMLDivElement;
  let imageRef: HTMLImageElement;
  let currentPoints: Array<{ x: number; y: number }> = $state([]);
  let isDrawing = $state(false);
  let imageLoaded = $state(false);
  let imageDimensions = $state({ width: 0, height: 0 });

  // Colors for different regions
  const regionColors = [
    'rgba(124, 58, 237, 0.3)', // purple
    'rgba(34, 197, 94, 0.3)', // green
    'rgba(59, 130, 246, 0.3)', // blue
    'rgba(249, 115, 22, 0.3)', // orange
    'rgba(236, 72, 153, 0.3)' // pink
  ];

  function handleImageLoad(e: Event) {
    const img = e.target as HTMLImageElement;
    imageDimensions = { width: img.naturalWidth, height: img.naturalHeight };
    imageLoaded = true;
  }

  function getRelativePosition(e: MouseEvent | TouchEvent): { x: number; y: number } | null {
    if (!imageRef) return null;

    const rect = imageRef.getBoundingClientRect();
    let clientX: number, clientY: number;

    if ('touches' in e) {
      if (e.touches.length === 0) return null;
      clientX = e.touches[0].clientX;
      clientY = e.touches[0].clientY;
    } else {
      clientX = e.clientX;
      clientY = e.clientY;
    }

    // Calculate position relative to image (0-1 range)
    const x = (clientX - rect.left) / rect.width;
    const y = (clientY - rect.top) / rect.height;

    // Clamp to image bounds
    return {
      x: Math.max(0, Math.min(1, x)),
      y: Math.max(0, Math.min(1, y))
    };
  }

  function handlePointerDown(e: MouseEvent | TouchEvent) {
    if (!editable) return;

    const pos = getRelativePosition(e);
    if (!pos) return;

    e.preventDefault();
    isDrawing = true;
    currentPoints = [pos];
  }

  function handlePointerMove(e: MouseEvent | TouchEvent) {
    if (!isDrawing || !editable) return;

    const pos = getRelativePosition(e);
    if (!pos) return;

    e.preventDefault();

    // Only add point if it's far enough from the last point
    const lastPoint = currentPoints[currentPoints.length - 1];
    const dx = pos.x - lastPoint.x;
    const dy = pos.y - lastPoint.y;
    const distance = Math.sqrt(dx * dx + dy * dy);

    if (distance > 0.01) {
      // Minimum distance threshold
      currentPoints = [...currentPoints, pos];
    }
  }

  function handlePointerUp(e: MouseEvent | TouchEvent) {
    if (!isDrawing || !editable) return;

    e.preventDefault();
    isDrawing = false;

    if (currentPoints.length >= 3) {
      // Convert normalized coords to image pixel coords
      const pixelPoints = currentPoints.map((p) => ({
        x: p.x * imageDimensions.width,
        y: p.y * imageDimensions.height
      }));

      const newRegion: FoodRegion = {
        id: crypto.randomUUID(),
        boundary: pixelPoints,
        estimatedAreaMm2: 0
      };

      const updatedRegions = [...regions, newRegion];
      onRegionComplete?.(newRegion);
      onRegionsChange?.(updatedRegions);
    }

    currentPoints = [];
  }

  function removeRegion(id: string) {
    const updatedRegions = regions.filter((r) => r.id !== id);
    onRegionsChange?.(updatedRegions);
  }

  function clearAllRegions() {
    onRegionsChange?.([]);
  }

  // Convert normalized points to SVG path
  function pointsToPath(points: Array<{ x: number; y: number }>, normalize: boolean): string {
    if (points.length < 2) return '';

    const first = points[0];
    let d = normalize ? `M ${first.x * 100}% ${first.y * 100}%` : `M ${first.x} ${first.y}`;

    for (let i = 1; i < points.length; i++) {
      const p = points[i];
      d += normalize ? ` L ${p.x * 100}% ${p.y * 100}%` : ` L ${p.x} ${p.y}`;
    }

    return d + ' Z';
  }

  // Convert pixel points to percentage for SVG
  function pixelPointsToSvgPath(points: Array<{ x: number; y: number }>): string {
    if (points.length < 2 || imageDimensions.width === 0) return '';

    const first = points[0];
    const fx = (first.x / imageDimensions.width) * 100;
    const fy = (first.y / imageDimensions.height) * 100;
    let d = `M ${fx} ${fy}`;

    for (let i = 1; i < points.length; i++) {
      const p = points[i];
      const px = (p.x / imageDimensions.width) * 100;
      const py = (p.y / imageDimensions.height) * 100;
      d += ` L ${px} ${py}`;
    }

    return d + ' Z';
  }
</script>

<div class="relative" bind:this={containerRef}>
  <!-- Image -->
  <img
    bind:this={imageRef}
    src={imageUrl}
    alt="Food to estimate"
    class="w-full rounded-lg"
    onload={handleImageLoad}
    draggable="false"
  />

  <!-- SVG overlay for regions -->
  {#if imageLoaded}
    <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
    <svg
      class="absolute inset-0 h-full w-full touch-none"
      viewBox="0 0 100 100"
      preserveAspectRatio="none"
      role="img"
      aria-label="Food region selection canvas"
      onmousedown={handlePointerDown}
      onmousemove={handlePointerMove}
      onmouseup={handlePointerUp}
      onmouseleave={handlePointerUp}
      ontouchstart={handlePointerDown}
      ontouchmove={handlePointerMove}
      ontouchend={handlePointerUp}
    >
      <!-- Existing regions -->
      {#each regions as region, i (region.id)}
        <path
          d={pixelPointsToSvgPath(region.boundary)}
          fill={regionColors[i % regionColors.length]}
          stroke={regionColors[i % regionColors.length].replace('0.3', '1')}
          stroke-width="0.5"
          vector-effect="non-scaling-stroke"
        />
      {/each}

      <!-- Current drawing -->
      {#if currentPoints.length >= 2}
        <path
          d={pointsToPath(
            currentPoints.map((p) => ({ x: p.x * 100, y: p.y * 100 })),
            false
          )}
          fill="rgba(124, 58, 237, 0.2)"
          stroke="rgba(124, 58, 237, 0.8)"
          stroke-width="0.5"
          stroke-dasharray="2,2"
          vector-effect="non-scaling-stroke"
        />
      {/if}
    </svg>
  {/if}

  <!-- Region labels/controls -->
  {#if regions.length > 0 && editable}
    <div class="absolute right-2 top-2 flex flex-col gap-1">
      {#each regions as region, i (region.id)}
        <button
          type="button"
          class="flex items-center gap-1 rounded-full px-2 py-1 text-xs text-white shadow-lg"
          style="background-color: {regionColors[i % regionColors.length].replace('0.3', '0.9')}"
          onclick={() => removeRegion(region.id)}
        >
          Region {i + 1}
          <span class="ml-1">&times;</span>
        </button>
      {/each}
    </div>
  {/if}

  <!-- Instructions overlay -->
  {#if editable && regions.length === 0 && !isDrawing}
    <div class="pointer-events-none absolute inset-0 flex items-center justify-center">
      <div class="rounded-lg bg-black/60 px-4 py-2 text-center text-white">
        <p class="text-sm font-medium">Draw around the food</p>
        <p class="text-xs text-gray-300">Touch and drag to outline</p>
      </div>
    </div>
  {/if}
</div>

<!-- Controls -->
{#if editable && regions.length > 0}
  <div class="mt-3 flex justify-between">
    <button type="button" class="text-sm text-gray-400 hover:text-white" onclick={clearAllRegions}>
      Clear all
    </button>
    <p class="text-sm text-gray-400">
      {regions.length} region{regions.length !== 1 ? 's' : ''} selected
    </p>
  </div>
{/if}
