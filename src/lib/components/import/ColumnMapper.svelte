<script lang="ts">
  /**
   * Workstream D: Column Mapper Component
   * Branch: dev-4
   *
   * Allows users to map CSV columns to expected fields for generic imports.
   */
  import type { CSVColumnMapping, BSLUnit } from '$lib/types';

  interface Props {
    columns: string[];
    suggestedMapping?: CSVColumnMapping | null;
    onMappingChange: (mapping: CSVColumnMapping, unit: BSLUnit) => void;
  }

  let { columns, suggestedMapping = null, onMappingChange }: Props = $props();

  let timestampColumn = $state(suggestedMapping?.timestampColumn ?? '');
  let valueColumn = $state(suggestedMapping?.valueColumn ?? '');
  let unitColumn = $state(suggestedMapping?.unitColumn ?? '');
  let deviceColumn = $state(suggestedMapping?.deviceColumn ?? '');
  let defaultUnit = $state<BSLUnit>('mmol/L');

  // Update parent when mapping changes
  $effect(() => {
    if (timestampColumn && valueColumn) {
      onMappingChange(
        {
          timestampColumn,
          valueColumn,
          unitColumn: unitColumn || undefined,
          deviceColumn: deviceColumn || undefined
        },
        defaultUnit
      );
    }
  });

  const isValid = $derived(timestampColumn !== '' && valueColumn !== '');
</script>

<div class="space-y-6">
  <div class="rounded-lg bg-gray-800/50 border border-gray-700 p-4">
    <p class="text-sm text-gray-400">
      We couldn't automatically detect the column format. Please map the columns below.
    </p>
  </div>

  <!-- Required Fields -->
  <div class="space-y-4">
    <h3 class="font-medium text-white">Required Fields</h3>

    <div>
      <label for="timestamp-col" class="mb-1 block text-sm font-medium text-gray-400">
        Timestamp Column <span class="text-red-400">*</span>
      </label>
      <select
        id="timestamp-col"
        bind:value={timestampColumn}
        class="w-full rounded-lg border border-gray-600 bg-gray-800 px-4 py-2.5 text-white focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      >
        <option value="">Select column...</option>
        {#each columns as col (col)}
          <option value={col}>{col}</option>
        {/each}
      </select>
    </div>

    <div>
      <label for="value-col" class="mb-1 block text-sm font-medium text-gray-400">
        Glucose Value Column <span class="text-red-400">*</span>
      </label>
      <select
        id="value-col"
        bind:value={valueColumn}
        class="w-full rounded-lg border border-gray-600 bg-gray-800 px-4 py-2.5 text-white focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      >
        <option value="">Select column...</option>
        {#each columns as col (col)}
          <option value={col}>{col}</option>
        {/each}
      </select>
    </div>

    <div>
      <label for="default-unit" class="mb-1 block text-sm font-medium text-gray-400">
        Value Unit <span class="text-red-400">*</span>
      </label>
      <select
        id="default-unit"
        bind:value={defaultUnit}
        class="w-full rounded-lg border border-gray-600 bg-gray-800 px-4 py-2.5 text-white focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      >
        <option value="mmol/L">mmol/L</option>
        <option value="mg/dL">mg/dL</option>
      </select>
    </div>
  </div>

  <!-- Optional Fields -->
  <div class="space-y-4">
    <h3 class="font-medium text-white">Optional Fields</h3>

    <div>
      <label for="unit-col" class="mb-1 block text-sm font-medium text-gray-400">
        Unit Column (if units vary per row)
      </label>
      <select
        id="unit-col"
        bind:value={unitColumn}
        class="w-full rounded-lg border border-gray-600 bg-gray-800 px-4 py-2.5 text-white focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      >
        <option value="">None</option>
        {#each columns as col (col)}
          <option value={col}>{col}</option>
        {/each}
      </select>
    </div>

    <div>
      <label for="device-col" class="mb-1 block text-sm font-medium text-gray-400">
        Device Column
      </label>
      <select
        id="device-col"
        bind:value={deviceColumn}
        class="w-full rounded-lg border border-gray-600 bg-gray-800 px-4 py-2.5 text-white focus:border-brand-accent focus:outline-none focus:ring-1 focus:ring-brand-accent"
      >
        <option value="">None</option>
        {#each columns as col (col)}
          <option value={col}>{col}</option>
        {/each}
      </select>
    </div>
  </div>

  <!-- Validation Status -->
  {#if !isValid}
    <p class="text-sm text-yellow-400">
      Please select both timestamp and value columns to continue.
    </p>
  {/if}
</div>
