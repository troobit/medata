<script lang="ts">
  /**
   * Axis Range Input Component
   *
   * Allows users to manually specify or adjust axis ranges
   * if auto-detection is incorrect.
   */
  import type { AxisRanges } from '$lib/types/cgm';
  import type { BSLUnit } from '$lib/types/events';

  interface Props {
    ranges: AxisRanges;
    onRangesChanged: (ranges: AxisRanges) => void;
    disabled?: boolean;
  }

  let { ranges, onRangesChanged, disabled = false }: Props = $props();

  // Local state for form inputs - initialized empty, synced via $effect
  let timeStartStr = $state('');
  let timeEndStr = $state('');
  let bslMin = $state(0);
  let bslMax = $state(0);
  let unit = $state<BSLUnit>('mmol/L');

  function formatTimeForInput(date: Date): string {
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  function parseTimeToDate(timeStr: string, referenceDate: Date): Date {
    const [hours, minutes] = timeStr.split(':').map(Number);
    const date = new Date(referenceDate);
    date.setHours(hours, minutes, 0, 0);
    return date;
  }

  function updateRanges() {
    const referenceDate = ranges.timeStart;
    const newRanges: AxisRanges = {
      timeStart: parseTimeToDate(timeStartStr, referenceDate),
      timeEnd: parseTimeToDate(timeEndStr, referenceDate),
      bslMin,
      bslMax,
      unit
    };

    // Handle overnight ranges (end time before start time means next day)
    if (newRanges.timeEnd <= newRanges.timeStart) {
      newRanges.timeEnd = new Date(newRanges.timeEnd.getTime() + 24 * 60 * 60 * 1000);
    }

    onRangesChanged(newRanges);
  }

  // Update local state when props change
  $effect(() => {
    timeStartStr = formatTimeForInput(ranges.timeStart);
    timeEndStr = formatTimeForInput(ranges.timeEnd);
    bslMin = ranges.bslMin;
    bslMax = ranges.bslMax;
    unit = ranges.unit;
  });

  // Typical ranges for different units
  const unitRanges = {
    'mmol/L': { min: 2, max: 25, step: 0.5, typical: { min: 2, max: 15 } },
    'mg/dL': { min: 36, max: 450, step: 5, typical: { min: 40, max: 400 } }
  };

  function handleUnitChange(newUnit: BSLUnit) {
    if (newUnit !== unit) {
      unit = newUnit;
      // Convert values
      if (newUnit === 'mg/dL') {
        bslMin = Math.round(bslMin * 18);
        bslMax = Math.round(bslMax * 18);
      } else {
        bslMin = Math.round((bslMin / 18) * 10) / 10;
        bslMax = Math.round((bslMax / 18) * 10) / 10;
      }
      updateRanges();
    }
  }
</script>

<div class="space-y-4 rounded-lg border border-gray-700 bg-gray-900/50 p-4">
  <div class="flex items-center justify-between">
    <h3 class="text-sm font-medium text-white">Axis Configuration</h3>
    <span class="text-xs text-gray-500">Adjust if detection is incorrect</span>
  </div>

  <!-- Time Range -->
  <div class="grid grid-cols-2 gap-4">
    <div>
      <label for="time-start" class="mb-1 block text-xs text-gray-400">Start Time</label>
      <input
        id="time-start"
        type="time"
        bind:value={timeStartStr}
        onchange={updateRanges}
        {disabled}
        class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none disabled:opacity-50"
      />
    </div>
    <div>
      <label for="time-end" class="mb-1 block text-xs text-gray-400">End Time</label>
      <input
        id="time-end"
        type="time"
        bind:value={timeEndStr}
        onchange={updateRanges}
        {disabled}
        class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none disabled:opacity-50"
      />
    </div>
  </div>

  <!-- Unit Selection -->
  <div>
    <span id="unit-label" class="mb-1 block text-xs text-gray-400">BSL Unit</span>
    <div class="grid grid-cols-2 gap-2" role="group" aria-labelledby="unit-label">
      <button
        type="button"
        class="rounded-lg px-3 py-2 text-sm font-medium transition-colors {unit === 'mmol/L'
          ? 'bg-brand-accent text-gray-950'
          : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
        onclick={() => handleUnitChange('mmol/L')}
        {disabled}
      >
        mmol/L
      </button>
      <button
        type="button"
        class="rounded-lg px-3 py-2 text-sm font-medium transition-colors {unit === 'mg/dL'
          ? 'bg-brand-accent text-gray-950'
          : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
        onclick={() => handleUnitChange('mg/dL')}
        {disabled}
      >
        mg/dL
      </button>
    </div>
  </div>

  <!-- BSL Range -->
  <div class="grid grid-cols-2 gap-4">
    <div>
      <label for="bsl-min" class="mb-1 block text-xs text-gray-400">Min BSL ({unit})</label>
      <input
        id="bsl-min"
        type="number"
        bind:value={bslMin}
        onchange={updateRanges}
        min={unitRanges[unit].min}
        max={bslMax - unitRanges[unit].step}
        step={unitRanges[unit].step}
        {disabled}
        class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none disabled:opacity-50"
      />
    </div>
    <div>
      <label for="bsl-max" class="mb-1 block text-xs text-gray-400">Max BSL ({unit})</label>
      <input
        id="bsl-max"
        type="number"
        bind:value={bslMax}
        onchange={updateRanges}
        min={bslMin + unitRanges[unit].step}
        max={unitRanges[unit].max}
        step={unitRanges[unit].step}
        {disabled}
        class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none disabled:opacity-50"
      />
    </div>
  </div>

  <!-- Typical ranges hint -->
  <p class="text-xs text-gray-500">
    Typical CGM range: {unitRanges[unit].typical.min} - {unitRanges[unit].typical.max} {unit}
  </p>
</div>
