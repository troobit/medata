<script lang="ts">
  /**
   * Extraction Preview Component
   *
   * Shows the extracted BSL curve overlaid on the original image
   * to verify extraction accuracy.
   */
  import type { CGMExtractionResult } from '$lib/types/cgm';

  interface Props {
    imageUrl: string;
    extractionResult: CGMExtractionResult;
  }

  let { imageUrl, extractionResult }: Props = $props();

  // Generate SVG path for the curve
  const curvePath = $derived.by(() => {
    const { axisRanges, dataPoints, graphRegion } = extractionResult;

    if (dataPoints.length < 2) return '';

    const timeRange = axisRanges.timeEnd.getTime() - axisRanges.timeStart.getTime();
    const bslRange = axisRanges.bslMax - axisRanges.bslMin;

    const points = dataPoints.map((point) => {
      // Calculate position as percentage within graph region
      const timeProgress = (point.timestamp.getTime() - axisRanges.timeStart.getTime()) / timeRange;
      const bslProgress = (point.value - axisRanges.bslMin) / bslRange;

      // Map to graph region coordinates (inverted Y for SVG)
      const x = graphRegion.x + timeProgress * graphRegion.width;
      const y = graphRegion.y + (1 - bslProgress) * graphRegion.height;

      return { x, y, confidence: point.confidence };
    });

    // Create SVG path
    let path = `M ${points[0].x} ${points[0].y}`;
    for (let i = 1; i < points.length; i++) {
      path += ` L ${points[i].x} ${points[i].y}`;
    }

    return path;
  });

  // Format time range for display
  const timeRangeStr = $derived(
    `${extractionResult.axisRanges.timeStart.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} - ${extractionResult.axisRanges.timeEnd.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`
  );

  // Calculate average confidence
  const avgConfidence = $derived(
    extractionResult.dataPoints.length > 0
      ? Math.round(
          (extractionResult.dataPoints.reduce((sum, p) => sum + p.confidence, 0) /
            extractionResult.dataPoints.length) *
            100
        )
      : 0
  );

  // Device type display names
  const deviceNames: Record<string, string> = {
    'freestyle-libre': 'Freestyle Libre',
    dexcom: 'Dexcom',
    medtronic: 'Medtronic',
    generic: 'Generic CGM'
  };
</script>

<div class="space-y-4">
  <!-- Image with overlay -->
  <div class="relative overflow-hidden rounded-lg">
    <img src={imageUrl} alt="CGM graph with extracted curve" class="w-full" />

    <!-- SVG overlay for extracted curve -->
    <svg
      class="pointer-events-none absolute inset-0 h-full w-full"
      viewBox="0 0 100 100"
      preserveAspectRatio="none"
    >
      {#if curvePath}
        <!-- Curve shadow for visibility -->
        <path
          d={curvePath}
          fill="none"
          stroke="rgba(0,0,0,0.5)"
          stroke-width="0.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
        <!-- Main curve -->
        <path
          d={curvePath}
          fill="none"
          stroke="#22c55e"
          stroke-width="0.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
        <!-- Data points -->
        {#each extractionResult.dataPoints as point, i}
          {@const timeRange =
            extractionResult.axisRanges.timeEnd.getTime() -
            extractionResult.axisRanges.timeStart.getTime()}
          {@const bslRange =
            extractionResult.axisRanges.bslMax - extractionResult.axisRanges.bslMin}
          {@const timeProgress =
            (point.timestamp.getTime() - extractionResult.axisRanges.timeStart.getTime()) /
            timeRange}
          {@const bslProgress = (point.value - extractionResult.axisRanges.bslMin) / bslRange}
          {@const x =
            extractionResult.graphRegion.x + timeProgress * extractionResult.graphRegion.width}
          {@const y =
            extractionResult.graphRegion.y +
            (1 - bslProgress) * extractionResult.graphRegion.height}
          {#if i % 3 === 0}
            <!-- Show every 3rd point to reduce clutter -->
            <circle
              cx={x}
              cy={y}
              r="0.8"
              fill={point.confidence > 0.7 ? '#22c55e' : '#eab308'}
              stroke="white"
              stroke-width="0.2"
            />
          {/if}
        {/each}
      {/if}
    </svg>

    <!-- Legend overlay -->
    <div class="absolute bottom-2 right-2 rounded bg-black/70 px-2 py-1 text-xs text-white">
      <span class="mr-2 inline-block h-2 w-2 rounded-full bg-green-500"></span>
      Extracted curve
    </div>
  </div>

  <!-- Extraction stats -->
  <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">Device</p>
      <p class="text-sm font-medium text-white">
        {deviceNames[extractionResult.deviceType] || extractionResult.deviceType}
      </p>
    </div>
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">Time Range</p>
      <p class="text-sm font-medium text-white">{timeRangeStr}</p>
    </div>
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">Data Points</p>
      <p class="text-sm font-medium text-white">{extractionResult.dataPoints.length}</p>
    </div>
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">Confidence</p>
      <p
        class="text-sm font-medium {avgConfidence >= 80
          ? 'text-green-400'
          : avgConfidence >= 60
            ? 'text-yellow-400'
            : 'text-red-400'}"
      >
        {avgConfidence}%
      </p>
    </div>
  </div>

  <!-- BSL range info -->
  <div class="rounded-lg border border-gray-700 bg-gray-900/50 px-4 py-3">
    <div class="flex items-center justify-between text-sm">
      <span class="text-gray-400">BSL Range:</span>
      <span class="font-medium text-white">
        {extractionResult.axisRanges.bslMin} - {extractionResult.axisRanges.bslMax}
        {extractionResult.axisRanges.unit}
      </span>
    </div>
  </div>

  <!-- Warnings -->
  {#if extractionResult.warnings && extractionResult.warnings.length > 0}
    <div class="rounded-lg border border-yellow-500/50 bg-yellow-500/10 px-4 py-3">
      <p class="mb-1 text-sm font-medium text-yellow-400">Warnings:</p>
      <ul class="list-inside list-disc text-sm text-yellow-300/80">
        {#each extractionResult.warnings as warning}
          <li>{warning}</li>
        {/each}
      </ul>
    </div>
  {/if}
</div>
