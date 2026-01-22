<script lang="ts">
  /**
   * Workstream D: Import Preview Component
   * Branch: dev-4
   *
   * Shows a preview of parsed CSV data before importing.
   */
  import type { ImportPreview, BSLUnit } from '$lib/types';

  interface Props {
    preview: ImportPreview;
    displayUnit?: BSLUnit;
  }

  let { preview, displayUnit = 'mmol/L' }: Props = $props();

  // Conversion for display
  const MMOL_TO_MGDL = 18.0182;

  function formatValue(value: number): string {
    if (displayUnit === 'mg/dL') {
      return Math.round(value * MMOL_TO_MGDL).toString();
    }
    return value.toFixed(1);
  }

  function formatDate(date: Date): string {
    return date.toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  const formatLabels: Record<string, string> = {
    'freestyle-libre': 'Freestyle Libre',
    dexcom: 'Dexcom Clarity',
    generic: 'Generic CSV'
  };
</script>

<div class="space-y-6">
  <!-- Summary Stats -->
  <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
    <div class="rounded-lg bg-gray-800 p-4">
      <p class="text-sm text-gray-400">Total Rows</p>
      <p class="text-2xl font-bold text-white">{preview.totalRows}</p>
    </div>
    <div class="rounded-lg bg-gray-800 p-4">
      <p class="text-sm text-gray-400">Valid</p>
      <p class="text-2xl font-bold text-green-400">{preview.validRows.length}</p>
    </div>
    <div class="rounded-lg bg-gray-800 p-4">
      <p class="text-sm text-gray-400">Invalid</p>
      <p
        class="text-2xl font-bold {preview.invalidRows.length > 0
          ? 'text-red-400'
          : 'text-gray-500'}"
      >
        {preview.invalidRows.length}
      </p>
    </div>
    <div class="rounded-lg bg-gray-800 p-4">
      <p class="text-sm text-gray-400">Duplicates</p>
      <p
        class="text-2xl font-bold {preview.duplicates.length > 0
          ? 'text-yellow-400'
          : 'text-gray-500'}"
      >
        {preview.duplicates.length}
      </p>
    </div>
  </div>

  <!-- Format and Date Range -->
  <div class="rounded-lg bg-gray-800 p-4">
    <div class="flex flex-wrap gap-4 text-sm">
      <div>
        <span class="text-gray-400">Format:</span>
        <span class="ml-2 text-white">{formatLabels[preview.format] ?? preview.format}</span>
      </div>
      <div>
        <span class="text-gray-400">Date Range:</span>
        <span class="ml-2 text-white">
          {formatDate(preview.dateRange.start)} – {formatDate(preview.dateRange.end)}
        </span>
      </div>
    </div>
  </div>

  <!-- Sample Data Preview -->
  <div>
    <h3 class="mb-3 font-medium text-white">Sample Data (first 5 rows)</h3>
    <div class="overflow-x-auto rounded-lg border border-gray-700">
      <table class="w-full text-sm">
        <thead class="bg-gray-800">
          <tr>
            <th class="px-4 py-3 text-left font-medium text-gray-400">Timestamp</th>
            <th class="px-4 py-3 text-left font-medium text-gray-400">Value ({displayUnit})</th>
            <th class="px-4 py-3 text-left font-medium text-gray-400">Device</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-700">
          {#each preview.sampleRows as row (row.lineNumber)}
            <tr class="bg-gray-900/50">
              <td class="px-4 py-3 text-gray-300">{formatDate(row.timestamp)}</td>
              <td class="px-4 py-3 font-mono text-white">{formatValue(row.value)}</td>
              <td class="px-4 py-3 text-gray-400">{row.device ?? '-'}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>

  <!-- Invalid Rows (if any) -->
  {#if preview.invalidRows.length > 0}
    <div>
      <h3 class="mb-3 font-medium text-red-400">
        Invalid Rows ({preview.invalidRows.length})
      </h3>
      <div class="max-h-40 overflow-y-auto rounded-lg border border-red-500/30 bg-red-500/10 p-4">
        <ul class="space-y-2 text-sm">
          {#each preview.invalidRows.slice(0, 10) as result (result.row.lineNumber)}
            <li class="text-red-300">
              <span class="font-mono">Line {result.row.lineNumber}:</span>
              {result.errors.join(', ')}
            </li>
          {/each}
          {#if preview.invalidRows.length > 10}
            <li class="text-gray-400">
              ... and {preview.invalidRows.length - 10} more
            </li>
          {/if}
        </ul>
      </div>
    </div>
  {/if}
</div>
