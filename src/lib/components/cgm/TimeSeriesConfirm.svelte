<script lang="ts">
  /**
   * Time Series Confirmation Component
   *
   * Shows extracted data points in a table/list format
   * for user review before importing.
   */
  import type { ExtractedDataPoint, AxisRanges } from '$lib/types/cgm';
  import { Button } from '$lib/components/ui';

  interface Props {
    dataPoints: ExtractedDataPoint[];
    axisRanges: AxisRanges;
    onConfirm: (points: ExtractedDataPoint[]) => void;
    onCancel: () => void;
    loading?: boolean;
  }

  let { dataPoints, axisRanges, onConfirm, onCancel, loading = false }: Props = $props();

  // State for editable points - initialized via $effect
  // Using state + effect pattern since points are modified by user
  // eslint-disable-next-line svelte/prefer-writable-derived
  let editablePoints = $state<ExtractedDataPoint[]>([]);
  let showAllPoints = $state(false);

  // Sync from dataPoints prop
  $effect(() => {
    editablePoints = [...dataPoints];
  });

  // Filtered points for display
  const displayedPoints = $derived(showAllPoints ? editablePoints : editablePoints.slice(0, 12));

  // Summary stats
  const stats = $derived.by(() => {
    const values = editablePoints.map((p) => p.value);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const avg = values.reduce((a, b) => a + b, 0) / values.length;

    // Calculate time in range (4-10 mmol/L or 72-180 mg/dL)
    const inRangeMin = axisRanges.unit === 'mmol/L' ? 4 : 72;
    const inRangeMax = axisRanges.unit === 'mmol/L' ? 10 : 180;
    const inRange = values.filter((v) => v >= inRangeMin && v <= inRangeMax).length;
    const tirPercent = Math.round((inRange / values.length) * 100);

    return {
      min: min.toFixed(1),
      max: max.toFixed(1),
      avg: avg.toFixed(1),
      tirPercent,
      totalPoints: editablePoints.length
    };
  });

  function formatTime(date: Date): string {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function updatePointValue(index: number, newValue: number) {
    editablePoints = editablePoints.map((p, i) =>
      i === index ? { ...p, value: newValue, confidence: 1.0 } : p
    );
  }

  function removePoint(index: number) {
    editablePoints = editablePoints.filter((_, i) => i !== index);
  }

  function handleConfirm() {
    onConfirm(editablePoints);
  }

  // Confidence color coding
  function getConfidenceColor(confidence: number): string {
    if (confidence >= 0.8) return 'text-green-400';
    if (confidence >= 0.6) return 'text-yellow-400';
    return 'text-red-400';
  }
</script>

<div class="space-y-4">
  <!-- Summary Stats -->
  <div class="grid grid-cols-4 gap-2">
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">Min</p>
      <p class="text-lg font-bold text-white">
        {stats.min}
        <span class="text-xs font-normal text-gray-400">{axisRanges.unit}</span>
      </p>
    </div>
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">Avg</p>
      <p class="text-lg font-bold text-white">
        {stats.avg}
        <span class="text-xs font-normal text-gray-400">{axisRanges.unit}</span>
      </p>
    </div>
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">Max</p>
      <p class="text-lg font-bold text-white">
        {stats.max}
        <span class="text-xs font-normal text-gray-400">{axisRanges.unit}</span>
      </p>
    </div>
    <div class="rounded-lg bg-gray-800 px-3 py-2 text-center">
      <p class="text-xs text-gray-400">TIR</p>
      <p
        class="text-lg font-bold {stats.tirPercent >= 70
          ? 'text-green-400'
          : stats.tirPercent >= 50
            ? 'text-yellow-400'
            : 'text-red-400'}"
      >
        {stats.tirPercent}%
      </p>
    </div>
  </div>

  <!-- Data Points Table -->
  <div class="rounded-lg border border-gray-700 bg-gray-900/50">
    <div class="border-b border-gray-700 px-4 py-3">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-medium text-white">
          Data Points ({stats.totalPoints})
        </h3>
        <span class="text-xs text-gray-500">Tap values to edit</span>
      </div>
    </div>

    <div class="max-h-64 overflow-y-auto">
      <table class="w-full">
        <thead class="sticky top-0 bg-gray-900">
          <tr class="text-xs text-gray-400">
            <th class="px-4 py-2 text-left">Time</th>
            <th class="px-4 py-2 text-right">BSL ({axisRanges.unit})</th>
            <th class="px-4 py-2 text-right">Conf.</th>
            <th class="px-4 py-2 text-right"></th>
          </tr>
        </thead>
        <tbody>
          {#each displayedPoints as point, index (point.timestamp.getTime())}
            <tr class="border-t border-gray-800 hover:bg-gray-800/50">
              <td class="px-4 py-2 text-sm text-gray-300">
                {formatTime(point.timestamp)}
              </td>
              <td class="px-4 py-2 text-right">
                <input
                  type="number"
                  value={point.value}
                  step={axisRanges.unit === 'mmol/L' ? 0.1 : 1}
                  min={axisRanges.bslMin}
                  max={axisRanges.bslMax}
                  onchange={(e) =>
                    updatePointValue(
                      showAllPoints ? index : index,
                      parseFloat((e.target as HTMLInputElement).value)
                    )}
                  class="w-16 rounded border border-gray-700 bg-gray-800 px-2 py-1 text-right text-sm text-white focus:border-brand-accent focus:outline-none"
                />
              </td>
              <td class="px-4 py-2 text-right text-sm {getConfidenceColor(point.confidence)}">
                {Math.round(point.confidence * 100)}%
              </td>
              <td class="px-4 py-2 text-right">
                <button
                  type="button"
                  class="text-gray-500 hover:text-red-400"
                  onclick={() => removePoint(showAllPoints ? index : index)}
                  aria-label="Remove data point"
                >
                  <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                </button>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    {#if editablePoints.length > 12}
      <div class="border-t border-gray-700 px-4 py-2">
        <button
          type="button"
          class="w-full text-center text-sm text-brand-accent hover:underline"
          onclick={() => (showAllPoints = !showAllPoints)}
        >
          {showAllPoints ? 'Show less' : `Show all ${editablePoints.length} points`}
        </button>
      </div>
    {/if}
  </div>

  <!-- Note about source -->
  <p class="text-center text-xs text-gray-500">Data will be imported with source: "cgm-image"</p>

  <!-- Action Buttons -->
  <div class="flex gap-3">
    <Button variant="secondary" class="flex-1" onclick={onCancel} disabled={loading}>Cancel</Button>
    <Button
      variant="primary"
      class="flex-1"
      onclick={handleConfirm}
      disabled={editablePoints.length === 0}
      {loading}
    >
      Import {editablePoints.length} Readings
    </Button>
  </div>
</div>
