<script lang="ts">
  /**
   * Developer Tools Page
   *
   * Provides utilities for local development including:
   * - Loading test data
   * - Clearing database
   * - Viewing database stats
   */
  import { Button } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';
  import type { PhysiologicalEvent } from '$lib/types';

  let loading = $state(false);
  let clearing = $state(false);
  let message = $state<{ type: 'success' | 'error'; text: string } | null>(null);
  let stats = $state<{ total: number; bsl: number; meal: number; insulin: number; exercise: number } | null>(null);

  async function loadTestData() {
    loading = true;
    message = null;

    try {
      // Fetch the test data from static folder
      const response = await fetch('/test-data.json');
      if (!response.ok) {
        throw new Error('Test data not found. Run `npm run generate-test-data` first.');
      }

      const data = await response.json();
      if (!data.events || !Array.isArray(data.events)) {
        throw new Error('Invalid test data format');
      }

      // Convert string dates back to Date objects and import
      const events: PhysiologicalEvent[] = data.events.map((e: Record<string, unknown>) => ({
        id: e.id as string,
        timestamp: new Date(e.timestamp as string),
        eventType: e.eventType as PhysiologicalEvent['eventType'],
        value: e.value as number,
        metadata: e.metadata as Record<string, unknown>,
        createdAt: new Date(e.createdAt as string),
        updatedAt: new Date(e.updatedAt as string),
        synced: e.synced as boolean | undefined
      }));

      // Import events
      await eventsStore.importEvents(events);
      await refreshStats();

      message = { type: 'success', text: `Imported ${events.length} events successfully!` };
    } catch (error) {
      message = {
        type: 'error',
        text: error instanceof Error ? error.message : 'Failed to load test data'
      };
    } finally {
      loading = false;
    }
  }

  async function clearDatabase() {
    if (!confirm('Are you sure you want to clear all data? This cannot be undone.')) {
      return;
    }

    clearing = true;
    message = null;

    try {
      await eventsStore.clearAll();
      await refreshStats();
      message = { type: 'success', text: 'Database cleared successfully!' };
    } catch (error) {
      message = {
        type: 'error',
        text: error instanceof Error ? error.message : 'Failed to clear database'
      };
    } finally {
      clearing = false;
    }
  }

  async function refreshStats() {
    try {
      const allEvents = await eventsStore.exportAll();
      stats = {
        total: allEvents.length,
        bsl: allEvents.filter(e => e.eventType === 'bsl').length,
        meal: allEvents.filter(e => e.eventType === 'meal').length,
        insulin: allEvents.filter(e => e.eventType === 'insulin').length,
        exercise: allEvents.filter(e => e.eventType === 'exercise').length
      };
    } catch {
      stats = null;
    }
  }

  // Load stats on mount
  $effect(() => {
    refreshStats();
  });
</script>

<svelte:head>
  <title>Developer Tools - MeData</title>
</svelte:head>

<div class="px-4 py-6">
  <header class="mb-8">
    <h1 class="text-2xl font-bold text-white">Developer Tools</h1>
    <p class="mt-2 text-sm text-gray-400">
      Tools for local development and testing. Not available in production.
    </p>
  </header>

  {#if message}
    <div
      class="mb-6 rounded-lg px-4 py-3 {message.type === 'success'
        ? 'bg-green-500/20 text-green-400'
        : 'bg-red-500/20 text-red-400'}"
    >
      {message.text}
    </div>
  {/if}

  <!-- Database Stats -->
  <section class="mb-8">
    <h2 class="mb-4 text-lg font-semibold text-gray-200">Database Statistics</h2>
    {#if stats}
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <div class="rounded-lg bg-gray-800 p-4">
          <p class="text-2xl font-bold text-white">{stats.total}</p>
          <p class="text-sm text-gray-400">Total Events</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4">
          <p class="text-2xl font-bold text-yellow-400">{stats.bsl}</p>
          <p class="text-sm text-gray-400">BSL Readings</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4">
          <p class="text-2xl font-bold text-green-400">{stats.meal}</p>
          <p class="text-sm text-gray-400">Meals</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4">
          <p class="text-2xl font-bold text-blue-400">{stats.insulin}</p>
          <p class="text-sm text-gray-400">Insulin</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4">
          <p class="text-2xl font-bold text-orange-400">{stats.exercise}</p>
          <p class="text-sm text-gray-400">Exercise</p>
        </div>
      </div>
    {:else}
      <p class="text-gray-400">Loading stats...</p>
    {/if}
  </section>

  <!-- Test Data -->
  <section class="mb-8">
    <h2 class="mb-4 text-lg font-semibold text-gray-200">Test Data</h2>
    <p class="mb-4 text-sm text-gray-400">
      Load generated test data into the database. Run <code class="rounded bg-gray-700 px-1">npm run generate-test-data</code> first to create the test data file.
    </p>
    <div class="flex gap-3">
      <Button variant="primary" onclick={loadTestData} loading={loading} disabled={loading}>
        Load Test Data
      </Button>
      <Button variant="secondary" onclick={refreshStats}>
        Refresh Stats
      </Button>
    </div>
  </section>

  <!-- Danger Zone -->
  <section class="border-t border-gray-800 pt-6">
    <h2 class="mb-4 text-lg font-semibold text-red-400">Danger Zone</h2>
    <p class="mb-4 text-sm text-gray-400">
      These actions are destructive and cannot be undone.
    </p>
    <Button variant="secondary" onclick={clearDatabase} loading={clearing} disabled={clearing}>
      Clear All Data
    </Button>
  </section>

  <div class="mt-8">
    <Button href="/" variant="secondary" class="w-full">Back to Home</Button>
  </div>
</div>
