<script lang="ts">
  import type { BSLUnit } from '$lib/types';
  import type { ExtractedBSLReading } from '$lib/types/vision';

  interface EditableReading extends ExtractedBSLReading {
    included: boolean;
  }

  interface Props {
    readings: ExtractedBSLReading[];
    onReadingsChange: (readings: EditableReading[]) => void;
    class?: string;
  }

  let { readings, onReadingsChange, class: className = '' }: Props = $props();

  // Convert readings to editable format
  let editableReadings = $state<EditableReading[]>(readings.map((r) => ({ ...r, included: true })));

  // Sync when readings prop changes
  $effect(() => {
    editableReadings = readings.map((r) => ({ ...r, included: true }));
  });

  // Notify parent of changes
  $effect(() => {
    onReadingsChange(editableReadings);
  });

  function toggleAll(checked: boolean) {
    editableReadings = editableReadings.map((r) => ({ ...r, included: checked }));
  }

  function toggleReading(index: number) {
    editableReadings = editableReadings.map((r, i) =>
      i === index ? { ...r, included: !r.included } : r
    );
  }

  function updateValue(index: number, value: string) {
    const numValue = parseFloat(value);
    if (!isNaN(numValue) && numValue > 0) {
      editableReadings = editableReadings.map((r, i) =>
        i === index ? { ...r, value: numValue } : r
      );
    }
  }

  function updateUnit(index: number, unit: BSLUnit) {
    editableReadings = editableReadings.map((r, i) => (i === index ? { ...r, unit } : r));
  }

  function formatTime(date: Date): string {
    return new Intl.DateTimeFormat('en-AU', {
      hour: 'numeric',
      minute: '2-digit',
      hour12: true,
      day: 'numeric',
      month: 'short'
    }).format(date);
  }

  function getConfidenceColor(confidence: number): string {
    if (confidence >= 0.9) return 'text-green-400';
    if (confidence >= 0.7) return 'text-yellow-400';
    return 'text-red-400';
  }

  const allSelected = $derived(editableReadings.every((r) => r.included));
  const noneSelected = $derived(editableReadings.every((r) => !r.included));
  const selectedCount = $derived(editableReadings.filter((r) => r.included).length);
</script>

<div class={className}>
  <div class="mb-4 flex items-center justify-between">
    <div class="text-sm text-gray-400">
      {selectedCount} of {editableReadings.length} readings selected
    </div>
    <div class="flex gap-2">
      <button
        type="button"
        onclick={() => toggleAll(true)}
        disabled={allSelected}
        class="text-sm text-brand-accent hover:text-brand-accent/80 disabled:text-gray-600"
      >
        Select all
      </button>
      <span class="text-gray-600">|</span>
      <button
        type="button"
        onclick={() => toggleAll(false)}
        disabled={noneSelected}
        class="text-sm text-brand-accent hover:text-brand-accent/80 disabled:text-gray-600"
      >
        Deselect all
      </button>
    </div>
  </div>

  <div class="space-y-2">
    {#each editableReadings as reading, index (index)}
      <div
        class="flex items-center gap-3 rounded-lg bg-gray-800 p-3 transition-opacity
          {reading.included ? '' : 'opacity-50'}"
      >
        <button
          type="button"
          onclick={() => toggleReading(index)}
          class="flex h-6 w-6 shrink-0 items-center justify-center rounded border transition-colors
            {reading.included
            ? 'border-brand-accent bg-brand-accent text-gray-950'
            : 'border-gray-600 bg-transparent'}"
          aria-label={reading.included ? 'Exclude reading' : 'Include reading'}
        >
          {#if reading.included}
            <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                clip-rule="evenodd"
              />
            </svg>
          {/if}
        </button>

        <div class="min-w-0 flex-1">
          <div class="text-sm text-gray-400">{formatTime(reading.timestamp)}</div>
        </div>

        <input
          type="number"
          step="0.1"
          min="0"
          value={reading.value}
          oninput={(e) => updateValue(index, e.currentTarget.value)}
          class="w-20 rounded bg-gray-700 px-2 py-1 text-right text-white focus:outline-none focus:ring-1 focus:ring-brand-accent"
        />

        <select
          value={reading.unit}
          onchange={(e) => updateUnit(index, e.currentTarget.value as BSLUnit)}
          class="rounded bg-gray-700 px-2 py-1 text-white focus:outline-none focus:ring-1 focus:ring-brand-accent"
        >
          <option value="mmol/L">mmol/L</option>
          <option value="mg/dL">mg/dL</option>
        </select>

        <div class="w-12 text-right text-xs {getConfidenceColor(reading.confidence)}">
          {Math.round(reading.confidence * 100)}%
        </div>
      </div>
    {/each}
  </div>

  {#if editableReadings.length === 0}
    <div class="rounded-lg bg-gray-800 p-6 text-center text-gray-400">
      No readings extracted from the image
    </div>
  {/if}
</div>
