<script lang="ts">
  /**
   * AI Model Validation Dashboard
   * Admin interface for test data collection, accuracy metrics, and prompt enhancement
   */
  import { onMount } from 'svelte';
  import { Button, ExpandableSection } from '$lib/components/ui';
  import { validationStore } from '$lib/stores';
  import { generateSyntheticTestBatch } from '$lib/services/validation/SyntheticImageGenerator';
  import type { FoodCategory, GroundTruthSource, TestDatasetExport } from '$lib/types';

  // Tab state
  type TabId = 'dataset' | 'metrics' | 'corrections' | 'enhancements';
  let activeTab = $state<TabId>('dataset');

  // Filter state
  let categoryFilter = $state<FoodCategory | ''>('');
  let sourceFilter = $state<GroundTruthSource | ''>('');
  let providerFilter = $state<string>('');

  // UI state
  let importing = $state(false);
  let exporting = $state(false);
  let generatingSynthetic = $state(false);
  let importError = $state<string | null>(null);
  let importSuccess = $state<string | null>(null);

  // File input ref - bound to DOM element (not reactive state)
  let fileInput = $state<HTMLInputElement | null>(null);

  const tabs: Array<{ id: TabId; label: string; icon: string }> = [
    { id: 'dataset', label: 'Test Data', icon: '📸' },
    { id: 'metrics', label: 'Accuracy', icon: '📊' },
    { id: 'corrections', label: 'Corrections', icon: '✏️' },
    { id: 'enhancements', label: 'Prompts', icon: '🎯' }
  ];

  const categories: FoodCategory[] = [
    'grain',
    'protein',
    'vegetable',
    'fruit',
    'dairy',
    'fat',
    'beverage',
    'mixed',
    'snack',
    'other'
  ];

  const sources: GroundTruthSource[] = [
    'usda',
    'academic',
    'nutrition-label',
    'manual-weighed',
    'imported'
  ];

  // Load data on mount
  onMount(() => {
    loadData();
  });

  async function loadData() {
    await Promise.all([
      validationStore.loadTestEntries(),
      validationStore.loadValidationResults(),
      validationStore.loadCorrectionHistory(),
      validationStore.loadAccuracyMetrics(providerFilter || undefined, categoryFilter || undefined),
      validationStore.loadCorrectionPatterns(),
      validationStore.loadPromptEnhancements()
    ]);
  }

  // Filter handlers
  async function handleCategoryFilter() {
    if (categoryFilter) {
      await validationStore.loadTestEntriesByCategory(categoryFilter);
    } else {
      await validationStore.loadTestEntries();
    }
    await validationStore.loadAccuracyMetrics(
      providerFilter || undefined,
      categoryFilter || undefined
    );
  }

  async function handleSourceFilter() {
    if (sourceFilter) {
      await validationStore.loadTestEntriesBySource(sourceFilter);
    } else {
      await validationStore.loadTestEntries();
    }
  }

  async function handleProviderFilter() {
    await validationStore.loadAccuracyMetrics(
      providerFilter || undefined,
      categoryFilter || undefined
    );
  }

  // Export handler
  async function handleExport() {
    exporting = true;
    try {
      const data = await validationStore.exportTestDataset();
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `medata-test-dataset-${new Date().toISOString().split('T')[0]}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      importError = e instanceof Error ? e.message : 'Export failed';
    } finally {
      exporting = false;
    }
  }

  // Import handler
  async function handleImport() {
    fileInput?.click();
  }

  async function handleFileSelect(event: Event) {
    const target = event.target as HTMLInputElement;
    const file = target.files?.[0];
    if (!file) return;

    importing = true;
    importError = null;
    importSuccess = null;

    try {
      const text = await file.text();
      const data = JSON.parse(text) as TestDatasetExport;
      const result = await validationStore.importTestDataset(data);

      if (result.success) {
        importSuccess = `Imported ${result.imported} entries`;
      } else {
        importSuccess = `Imported ${result.imported} entries, skipped ${result.skipped}`;
        if (result.errors.length > 0) {
          importError = result.errors.map((e) => `Line ${e.line}: ${e.message}`).join('; ');
        }
      }
    } catch (e) {
      importError = e instanceof Error ? e.message : 'Import failed';
    } finally {
      importing = false;
      target.value = '';
    }
  }

  // Delete test entry
  async function handleDeleteEntry(id: string) {
    if (confirm('Delete this test entry?')) {
      await validationStore.deleteTestEntry(id);
    }
  }

  // Generate synthetic test data
  async function handleGenerateSynthetic() {
    generatingSynthetic = true;
    importError = null;
    importSuccess = null;

    try {
      const entries = generateSyntheticTestBatch();
      let created = 0;

      for (const entry of entries) {
        await validationStore.createTestEntry(entry);
        created++;
      }

      importSuccess = `Generated ${created} synthetic test images`;
    } catch (e) {
      importError = e instanceof Error ? e.message : 'Failed to generate synthetic data';
    } finally {
      generatingSynthetic = false;
    }
  }

  // Clear all data
  async function handleClearDataset() {
    if (confirm('Delete ALL test data? This cannot be undone.')) {
      await validationStore.clearTestDataset();
    }
  }

  async function handleClearResults() {
    if (confirm('Delete ALL validation results? This cannot be undone.')) {
      await validationStore.clearValidationResults();
    }
  }

  async function handleClearCorrections() {
    if (confirm('Delete ALL correction history? This cannot be undone.')) {
      await validationStore.clearCorrectionHistory();
    }
  }

  // Format helpers
  function formatDate(date: Date): string {
    return new Date(date).toLocaleDateString('en-AU', {
      day: 'numeric',
      month: 'short',
      year: '2-digit'
    });
  }

  function formatPercent(value: number): string {
    return `${value.toFixed(1)}%`;
  }

  function formatNumber(value: number): string {
    return value.toFixed(1);
  }

  function categoryLabel(cat: FoodCategory): string {
    return cat.charAt(0).toUpperCase() + cat.slice(1);
  }

  function sourceLabel(src: GroundTruthSource): string {
    const labels: Record<GroundTruthSource, string> = {
      usda: 'USDA',
      academic: 'Academic',
      'nutrition-label': 'Label',
      'manual-weighed': 'Weighed',
      imported: 'Imported'
    };
    return labels[src] || src;
  }

  function mapeColor(mape: number): string {
    if (mape <= 5) return 'text-green-400';
    if (mape <= 15) return 'text-yellow-400';
    return 'text-red-400';
  }
</script>

<svelte:head>
  <title>Validation - MeData</title>
</svelte:head>

<div class="min-h-[calc(100dvh-80px)] px-4 py-6">
  <!-- Header -->
  <header class="mb-6">
    <div class="mb-2 flex items-center justify-between">
      <h1 class="text-2xl font-bold text-white">AI Validation</h1>
      <a href="/settings" class="text-sm text-gray-400 hover:text-gray-200">Settings</a>
    </div>
    <p class="text-sm text-gray-400">Collect test data, track accuracy, and improve AI estimates</p>
  </header>

  <!-- Tab Navigation -->
  <nav class="mb-6 flex gap-1 rounded-lg bg-gray-800/50 p-1">
    {#each tabs as tab}
      <button
        type="button"
        class="flex flex-1 items-center justify-center gap-1.5 rounded-md px-3 py-2 text-sm font-medium transition-colors {activeTab ===
        tab.id
          ? 'bg-gray-700 text-white'
          : 'text-gray-400 hover:text-gray-200'}"
        onclick={() => (activeTab = tab.id)}
      >
        <span>{tab.icon}</span>
        <span class="hidden sm:inline">{tab.label}</span>
      </button>
    {/each}
  </nav>

  <!-- Error/Success Messages -->
  {#if validationStore.error}
    <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
      {validationStore.error}
    </div>
  {/if}

  {#if importError}
    <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
      {importError}
    </div>
  {/if}

  {#if importSuccess}
    <div class="mb-4 rounded-lg bg-green-500/20 px-4 py-3 text-green-400">
      {importSuccess}
    </div>
  {/if}

  <!-- Loading State -->
  {#if validationStore.loading}
    <div class="flex items-center justify-center py-12">
      <div
        class="h-8 w-8 animate-spin rounded-full border-2 border-brand-accent border-t-transparent"
      ></div>
    </div>
  {:else}
    <!-- Tab Content -->
    {#if activeTab === 'dataset'}
      <!-- Test Dataset Tab -->
      <div class="space-y-6">
        <!-- Stats Row -->
        <div class="grid grid-cols-3 gap-3">
          <div class="rounded-lg bg-gray-800/50 p-3 text-center">
            <div class="text-2xl font-bold text-white">{validationStore.testEntryCount}</div>
            <div class="text-xs text-gray-400">Test Images</div>
          </div>
          <div class="rounded-lg bg-gray-800/50 p-3 text-center">
            <div class="text-2xl font-bold text-white">{validationStore.validationResultCount}</div>
            <div class="text-xs text-gray-400">Validations</div>
          </div>
          <div class="rounded-lg bg-gray-800/50 p-3 text-center">
            <div class="text-2xl font-bold text-white">{validationStore.correctionCount}</div>
            <div class="text-xs text-gray-400">Corrections</div>
          </div>
        </div>

        <!-- Actions -->
        <div class="flex flex-wrap gap-2">
          <a href="/validation/capture" class="inline-flex">
            <Button variant="primary" size="sm">📸 Add Test Data</Button>
          </a>
          <Button
            variant="secondary"
            size="sm"
            onclick={handleGenerateSynthetic}
            loading={generatingSynthetic}
          >
            🎨 Generate Synthetic
          </Button>
          <Button variant="secondary" size="sm" onclick={handleExport} loading={exporting}>
            Export JSON
          </Button>
          <Button variant="secondary" size="sm" onclick={handleImport} loading={importing}>
            Import JSON
          </Button>
          <input
            bind:this={fileInput}
            type="file"
            accept=".json"
            class="hidden"
            onchange={handleFileSelect}
          />
        </div>

        <!-- Filters -->
        <div class="flex flex-wrap gap-3">
          <select
            bind:value={categoryFilter}
            onchange={handleCategoryFilter}
            class="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none"
          >
            <option value="">All Categories</option>
            {#each categories as cat}
              <option value={cat}>{categoryLabel(cat)}</option>
            {/each}
          </select>

          <select
            bind:value={sourceFilter}
            onchange={handleSourceFilter}
            class="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none"
          >
            <option value="">All Sources</option>
            {#each sources as src}
              <option value={src}>{sourceLabel(src)}</option>
            {/each}
          </select>
        </div>

        <!-- Test Entries List -->
        {#if validationStore.testEntries.length === 0}
          <div class="rounded-lg bg-gray-800/30 p-8 text-center">
            <p class="mb-2 text-gray-400">No test data yet</p>
            <p class="text-sm text-gray-500">
              Capture food images with known nutritional values to build your test dataset
            </p>
          </div>
        {:else}
          <div class="space-y-3">
            {#each validationStore.testEntries as entry}
              <div class="flex items-start gap-3 rounded-lg bg-gray-800/50 p-3">
                {#if entry.imageUrl}
                  <img
                    src={entry.imageUrl}
                    alt={entry.description || 'Test image'}
                    class="h-16 w-16 rounded-lg object-cover"
                  />
                {:else}
                  <div
                    class="flex h-16 w-16 items-center justify-center rounded-lg bg-gray-700 text-gray-500"
                  >
                    📷
                  </div>
                {/if}

                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2">
                    {#if entry.category}
                      <span class="rounded bg-gray-700 px-1.5 py-0.5 text-xs text-gray-300">
                        {categoryLabel(entry.category)}
                      </span>
                    {/if}
                    <span class="rounded bg-blue-500/20 px-1.5 py-0.5 text-xs text-blue-400">
                      {sourceLabel(entry.source)}
                    </span>
                  </div>

                  {#if entry.description}
                    <p class="mt-1 truncate text-sm text-white">{entry.description}</p>
                  {/if}

                  <div class="mt-1 flex flex-wrap gap-2 text-xs text-gray-400">
                    <span class="text-green-400">{entry.groundTruth.carbs}g carbs</span>
                    <span>{entry.groundTruth.protein}g protein</span>
                    <span>{entry.groundTruth.fat}g fat</span>
                    <span>{entry.groundTruth.calories} cal</span>
                  </div>

                  <div class="mt-1 text-xs text-gray-500">
                    {formatDate(entry.createdAt)}
                  </div>
                </div>

                <button
                  type="button"
                  onclick={() => handleDeleteEntry(entry.id)}
                  class="p-2 text-gray-500 hover:text-red-400"
                  title="Delete entry"
                >
                  <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                    />
                  </svg>
                </button>
              </div>
            {/each}
          </div>
        {/if}

        <!-- Danger Zone -->
        <ExpandableSection title="Danger Zone" subtitle="Clear all data" collapsed={true}>
          <div class="space-y-3">
            <Button
              variant="secondary"
              size="sm"
              onclick={handleClearDataset}
              class="w-full text-red-400"
            >
              Clear Test Dataset
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onclick={handleClearResults}
              class="w-full text-red-400"
            >
              Clear Validation Results
            </Button>
            <Button
              variant="secondary"
              size="sm"
              onclick={handleClearCorrections}
              class="w-full text-red-400"
            >
              Clear Correction History
            </Button>
          </div>
        </ExpandableSection>
      </div>
    {:else if activeTab === 'metrics'}
      <!-- Accuracy Metrics Tab -->
      <div class="space-y-6">
        <!-- Provider Filter -->
        <div class="flex gap-3">
          <select
            bind:value={providerFilter}
            onchange={handleProviderFilter}
            class="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none"
          >
            <option value="">All Providers</option>
            <option value="openai">OpenAI</option>
            <option value="gemini">Gemini</option>
            <option value="claude">Claude</option>
            <option value="foundry">Azure Foundry</option>
            <option value="azure">Azure OpenAI</option>
          </select>

          <select
            bind:value={categoryFilter}
            onchange={handleCategoryFilter}
            class="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:border-brand-accent focus:outline-none"
          >
            <option value="">All Categories</option>
            {#each categories as cat}
              <option value={cat}>{categoryLabel(cat)}</option>
            {/each}
          </select>
        </div>

        {#if validationStore.accuracyMetrics}
          <div class="rounded-lg bg-gray-800/50 p-4">
            <div class="mb-4 flex items-center justify-between">
              <h3 class="font-semibold text-white">Overall Accuracy</h3>
              <span class="text-sm text-gray-400">
                {validationStore.accuracyMetrics.sampleCount} samples
              </span>
            </div>

            {#if validationStore.accuracyMetrics.sampleCount > 0}
              <!-- MAPE Summary -->
              <div class="mb-4 grid grid-cols-2 gap-4 sm:grid-cols-4">
                <div class="text-center">
                  <div
                    class={`text-2xl font-bold ${mapeColor(validationStore.accuracyMetrics.mape.carbs)}`}
                  >
                    {formatPercent(validationStore.accuracyMetrics.mape.carbs)}
                  </div>
                  <div class="text-xs text-green-400">Carbs MAPE</div>
                </div>
                <div class="text-center">
                  <div
                    class={`text-2xl font-bold ${mapeColor(validationStore.accuracyMetrics.mape.protein)}`}
                  >
                    {formatPercent(validationStore.accuracyMetrics.mape.protein)}
                  </div>
                  <div class="text-xs text-blue-400">Protein MAPE</div>
                </div>
                <div class="text-center">
                  <div
                    class={`text-2xl font-bold ${mapeColor(validationStore.accuracyMetrics.mape.fat)}`}
                  >
                    {formatPercent(validationStore.accuracyMetrics.mape.fat)}
                  </div>
                  <div class="text-xs text-yellow-400">Fat MAPE</div>
                </div>
                <div class="text-center">
                  <div
                    class={`text-2xl font-bold ${mapeColor(validationStore.accuracyMetrics.mape.calories)}`}
                  >
                    {formatPercent(validationStore.accuracyMetrics.mape.calories)}
                  </div>
                  <div class="text-xs text-gray-400">Calories MAPE</div>
                </div>
              </div>

              <!-- MAE Summary -->
              <div class="mb-4 rounded-lg bg-gray-900/50 p-3">
                <div class="mb-2 text-xs text-gray-500">Mean Absolute Error (grams)</div>
                <div class="grid grid-cols-4 gap-2 text-center text-sm">
                  <div>
                    <span class="text-green-400"
                      >{formatNumber(validationStore.accuracyMetrics.mae.carbs)}g</span
                    >
                    <div class="text-xs text-gray-500">Carbs</div>
                  </div>
                  <div>
                    <span class="text-blue-400"
                      >{formatNumber(validationStore.accuracyMetrics.mae.protein)}g</span
                    >
                    <div class="text-xs text-gray-500">Protein</div>
                  </div>
                  <div>
                    <span class="text-yellow-400"
                      >{formatNumber(validationStore.accuracyMetrics.mae.fat)}g</span
                    >
                    <div class="text-xs text-gray-500">Fat</div>
                  </div>
                  <div>
                    <span class="text-gray-300"
                      >{formatNumber(validationStore.accuracyMetrics.mae.calories)}</span
                    >
                    <div class="text-xs text-gray-500">Calories</div>
                  </div>
                </div>
              </div>

              <!-- Additional Metrics -->
              <div class="flex justify-between text-sm text-gray-400">
                <span
                  >Avg Confidence: {formatPercent(
                    validationStore.accuracyMetrics.avgConfidence * 100
                  )}</span
                >
                <span
                  >Avg Time: {Math.round(
                    validationStore.accuracyMetrics.avgProcessingTimeMs
                  )}ms</span
                >
              </div>
            {:else}
              <p class="text-center text-gray-400">
                No validation results yet. Run validations against test data to see metrics.
              </p>
            {/if}
          </div>

          <!-- Requirement Check -->
          <div class="rounded-lg bg-gray-800/50 p-4">
            <h3 class="mb-3 font-semibold text-white">Requirement: 5% Accuracy Target</h3>
            {#if validationStore.accuracyMetrics.sampleCount > 0}
              <div class="space-y-2">
                {#each [{ label: 'Carbs', value: validationStore.accuracyMetrics.mape.carbs, colour: 'green' }, { label: 'Protein', value: validationStore.accuracyMetrics.mape.protein, colour: 'blue' }, { label: 'Fat', value: validationStore.accuracyMetrics.mape.fat, colour: 'yellow' }, { label: 'Calories', value: validationStore.accuracyMetrics.mape.calories, colour: 'gray' }] as metric}
                  <div class="flex items-center gap-3">
                    <span class="w-20 text-sm text-gray-400">{metric.label}</span>
                    <div class="flex-1 h-2 rounded-full bg-gray-700">
                      <div
                        class="h-2 rounded-full transition-all {metric.value <= 5
                          ? 'bg-green-500'
                          : metric.value <= 15
                            ? 'bg-yellow-500'
                            : 'bg-red-500'}"
                        style="width: {Math.min((metric.value / 30) * 100, 100)}%"
                      ></div>
                    </div>
                    <span
                      class="w-16 text-right text-sm {metric.value <= 5
                        ? 'text-green-400'
                        : 'text-gray-400'}"
                    >
                      {formatPercent(metric.value)}
                    </span>
                    {#if metric.value <= 5}
                      <span class="text-green-400">✓</span>
                    {:else}
                      <span class="text-gray-500">○</span>
                    {/if}
                  </div>
                {/each}
              </div>
            {:else}
              <p class="text-gray-400">Add test data and run validations to check accuracy.</p>
            {/if}
          </div>
        {:else}
          <p class="text-center text-gray-400">Loading metrics...</p>
        {/if}
      </div>
    {:else if activeTab === 'corrections'}
      <!-- Corrections Tab -->
      <div class="space-y-6">
        <div class="rounded-lg bg-gray-800/50 p-4">
          <h3 class="mb-3 font-semibold text-white">User Corrections</h3>
          <p class="mb-4 text-sm text-gray-400">
            When users edit AI estimates, corrections are recorded to improve future predictions.
          </p>

          {#if validationStore.correctionHistory.length === 0}
            <p class="text-center text-gray-500">
              No corrections recorded yet. Corrections are captured when users edit AI meal
              estimates.
            </p>
          {:else}
            <div class="space-y-3">
              {#each validationStore.correctionHistory.slice(0, 20) as correction}
                <div class="rounded-lg bg-gray-900/50 p-3">
                  <div class="mb-2 flex items-center justify-between">
                    <span class="text-sm text-gray-400">{correction.aiProvider}</span>
                    <span class="text-xs text-gray-500">{formatDate(correction.timestamp)}</span>
                  </div>

                  {#if correction.category}
                    <span
                      class="mb-2 inline-block rounded bg-gray-700 px-1.5 py-0.5 text-xs text-gray-300"
                    >
                      {categoryLabel(correction.category)}
                    </span>
                  {/if}

                  <div class="grid grid-cols-2 gap-2 text-sm">
                    <div>
                      <div class="text-xs text-gray-500">AI Predicted</div>
                      <div class="text-gray-300">
                        {correction.aiPrediction.carbs}g carbs
                      </div>
                    </div>
                    <div>
                      <div class="text-xs text-gray-500">User Corrected</div>
                      <div class="text-green-400">
                        {correction.userCorrection.carbs}g carbs
                      </div>
                    </div>
                  </div>

                  <div class="mt-1 text-xs text-gray-500">
                    Difference: {correction.userCorrection.carbs - correction.aiPrediction.carbs > 0
                      ? '+'
                      : ''}{correction.userCorrection.carbs - correction.aiPrediction.carbs}g ({correction.aiConfidence >
                    0
                      ? `${Math.round(correction.aiConfidence * 100)}% confidence`
                      : 'N/A'})
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        </div>

        <!-- Correction Patterns -->
        {#if validationStore.correctionPatterns.length > 0}
          <div class="rounded-lg bg-gray-800/50 p-4">
            <h3 class="mb-3 font-semibold text-white">Correction Patterns by Category</h3>
            <div class="space-y-3">
              {#each validationStore.correctionPatterns as pattern}
                <div class="rounded-lg bg-gray-900/50 p-3">
                  <div class="mb-2 flex items-center justify-between">
                    <span class="font-medium text-white">{categoryLabel(pattern.category)}</span>
                    <span class="text-xs text-gray-500">{pattern.correctionCount} corrections</span>
                  </div>

                  <div class="grid grid-cols-2 gap-2 text-xs">
                    <div>
                      <div class="text-gray-500">Avg Overestimation</div>
                      <div class="text-red-400">
                        Carbs: +{formatNumber(pattern.avgOverestimation.carbs)}g
                      </div>
                    </div>
                    <div>
                      <div class="text-gray-500">Avg Underestimation</div>
                      <div class="text-blue-400">
                        Carbs: -{formatNumber(pattern.avgUnderestimation.carbs)}g
                      </div>
                    </div>
                  </div>
                </div>
              {/each}
            </div>
          </div>
        {/if}
      </div>
    {:else if activeTab === 'enhancements'}
      <!-- Prompt Enhancements Tab -->
      <div class="space-y-6">
        <div class="rounded-lg bg-gray-800/50 p-4">
          <h3 class="mb-3 font-semibold text-white">Prompt Enhancement Suggestions</h3>
          <p class="mb-4 text-sm text-gray-400">
            Based on correction patterns, these adjustments could improve AI estimates.
          </p>

          {#if validationStore.promptEnhancements.length === 0}
            <p class="text-center text-gray-500">
              Not enough correction data to generate suggestions. Keep using the app and correcting
              estimates.
            </p>
          {:else}
            <div class="space-y-3">
              {#each validationStore.promptEnhancements as enhancement}
                <div class="rounded-lg bg-gray-900/50 p-3">
                  <div class="mb-2 flex items-center justify-between">
                    <span class="font-medium text-white">{categoryLabel(enhancement.category)}</span
                    >
                    <span
                      class="rounded px-1.5 py-0.5 text-xs {enhancement.adjustment === 'decrease'
                        ? 'bg-red-500/20 text-red-400'
                        : 'bg-green-500/20 text-green-400'}"
                    >
                      {enhancement.adjustment === 'decrease' ? '↓' : '↑'}
                      {enhancement.field}
                    </span>
                  </div>

                  <p class="text-sm text-gray-300">
                    {enhancement.adjustment === 'decrease' ? 'Reduce' : 'Increase'}
                    {enhancement.field} estimates by ~{formatPercent(
                      enhancement.percentageAdjustment
                    )} for {categoryLabel(enhancement.category)} foods.
                  </p>

                  <div class="mt-2 flex items-center justify-between text-xs text-gray-500">
                    <span>Confidence: {formatPercent(enhancement.confidence * 100)}</span>
                    <span>Based on {enhancement.sampleSize} samples</span>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        </div>

        <!-- Instructions for Manual Prompt Updates -->
        <div class="rounded-lg bg-blue-500/10 p-4">
          <h4 class="mb-2 font-medium text-blue-400">How to Apply Enhancements</h4>
          <p class="text-sm text-gray-300">
            These suggestions can be incorporated into the AI prompt by modifying
            <code class="rounded bg-gray-800 px-1 text-xs"
              >src/lib/services/ai/prompts/foodRecognition.ts</code
            >. Add category-specific adjustment factors based on the patterns above.
          </p>
        </div>
      </div>
    {/if}
  {/if}
</div>
