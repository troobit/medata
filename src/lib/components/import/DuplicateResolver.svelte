<script lang="ts">
  /**
   * Workstream D: Duplicate Resolver Component
   * Branch: dev-4
   *
   * UI for selecting how to handle duplicate entries during import.
   */
  import type { DuplicateMatch, DuplicateStrategy } from '$lib/types';
  import { getDuplicateStats } from '$lib/services/import';

  interface Props {
    duplicates: DuplicateMatch[];
    selectedStrategy: DuplicateStrategy;
    onStrategyChange: (strategy: DuplicateStrategy) => void;
  }

  let { duplicates, selectedStrategy, onStrategyChange }: Props = $props();

  const stats = $derived(getDuplicateStats(duplicates));

  const strategies: { value: DuplicateStrategy; label: string; description: string }[] = [
    {
      value: 'skip',
      label: 'Skip duplicates',
      description: 'Do not import rows that match existing data'
    },
    {
      value: 'keep-existing',
      label: 'Keep existing',
      description: 'Same as skip - preserve existing data'
    },
    {
      value: 'keep-import',
      label: 'Replace with import',
      description: 'Delete existing and import new data'
    },
    {
      value: 'keep-both',
      label: 'Keep both',
      description: 'Import all data, even if duplicates exist'
    }
  ];

  function formatTimeDiff(ms: number): string {
    const minutes = Math.round(ms / 60000);
    if (minutes === 0) return 'same time';
    return `${minutes} min apart`;
  }
</script>

<div class="space-y-6">
  <!-- Duplicate Stats -->
  <div class="rounded-lg bg-yellow-500/10 border border-yellow-500/30 p-4">
    <div class="flex items-start gap-3">
      <div class="text-2xl">⚠️</div>
      <div>
        <p class="font-medium text-yellow-400">
          {stats.total} potential duplicate{stats.total !== 1 ? 's' : ''} found
        </p>
        <p class="mt-1 text-sm text-gray-400">
          {stats.exact} exact match{stats.exact !== 1 ? 'es' : ''},
          {stats.near} near match{stats.near !== 1 ? 'es' : ''} (within 5 minutes)
        </p>
      </div>
    </div>
  </div>

  <!-- Strategy Selection -->
  <div>
    <h3 class="mb-3 font-medium text-white">How would you like to handle duplicates?</h3>
    <div class="space-y-2">
      {#each strategies as strategy (strategy.value)}
        <label
          class="flex cursor-pointer items-start gap-3 rounded-lg border p-4 transition-colors {selectedStrategy === strategy.value
            ? 'border-brand-accent bg-brand-accent/10'
            : 'border-gray-700 bg-gray-800/50 hover:border-gray-600'}"
        >
          <input
            type="radio"
            name="duplicate-strategy"
            value={strategy.value}
            checked={selectedStrategy === strategy.value}
            onchange={() => onStrategyChange(strategy.value)}
            class="mt-1 h-4 w-4 border-gray-600 bg-gray-700 text-brand-accent focus:ring-brand-accent"
          />
          <div>
            <p class="font-medium text-white">{strategy.label}</p>
            <p class="text-sm text-gray-400">{strategy.description}</p>
          </div>
        </label>
      {/each}
    </div>
  </div>

  <!-- Sample Duplicates -->
  {#if duplicates.length > 0}
    <div>
      <h3 class="mb-3 font-medium text-white">Sample duplicates</h3>
      <div class="max-h-48 overflow-y-auto rounded-lg border border-gray-700 bg-gray-800/50">
        <table class="w-full text-sm">
          <thead class="sticky top-0 bg-gray-800">
            <tr>
              <th class="px-4 py-2 text-left font-medium text-gray-400">Import Row</th>
              <th class="px-4 py-2 text-left font-medium text-gray-400">Existing</th>
              <th class="px-4 py-2 text-left font-medium text-gray-400">Match</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-700">
            {#each duplicates.slice(0, 5) as dup (dup.importRow.lineNumber)}
              <tr>
                <td class="px-4 py-2 text-gray-300">
                  {dup.importRow.value.toFixed(1)} mmol/L
                  <br />
                  <span class="text-xs text-gray-500">
                    {dup.importRow.timestamp.toLocaleString()}
                  </span>
                </td>
                <td class="px-4 py-2 text-gray-300">
                  {dup.existingEvent.value.toFixed(1)} mmol/L
                  <br />
                  <span class="text-xs text-gray-500">
                    {new Date(dup.existingEvent.timestamp).toLocaleString()}
                  </span>
                </td>
                <td class="px-4 py-2">
                  <span
                    class="inline-block rounded px-2 py-0.5 text-xs {dup.matchType === 'exact'
                      ? 'bg-red-500/20 text-red-400'
                      : 'bg-yellow-500/20 text-yellow-400'}"
                  >
                    {dup.matchType === 'exact' ? 'Exact' : formatTimeDiff(dup.timeDifferenceMs)}
                  </span>
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      {#if duplicates.length > 5}
        <p class="mt-2 text-sm text-gray-500">
          Showing 5 of {duplicates.length} duplicates
        </p>
      {/if}
    </div>
  {/if}
</div>
