<script lang="ts">
  import { Button, EmptyState } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';
  import { onMount } from 'svelte';

  onMount(() => {
    eventsStore.loadToday();
  });

  // Get today's stats from events
  const todayStats = $derived.by(() => {
    const events = eventsStore.events;
    const insulinEvents = events.filter((e) => e.eventType === 'insulin');
    const mealEvents = events.filter((e) => e.eventType === 'meal');
    const bslEvents = events.filter((e) => e.eventType === 'bsl');

    const totalInsulin = insulinEvents.reduce((sum, e) => sum + e.value, 0);
    const totalCarbs = mealEvents.reduce((sum, e) => sum + e.value, 0);
    const avgBSL =
      bslEvents.length > 0
        ? bslEvents.reduce((sum, e) => sum + e.value, 0) / bslEvents.length
        : null;

    return {
      totalInsulin,
      totalCarbs,
      avgBSL,
      eventCount: events.length
    };
  });
</script>

<div class="px-4 py-6">
  <!-- Header -->
  <header class="mb-8">
    <h1 class="text-2xl font-bold text-white">MeData</h1>
    <p class="mt-1 text-gray-400">Track your health data</p>
  </header>

  <!-- Quick Actions -->
  <section class="mb-8">
    <h2 class="mb-4 text-lg font-semibold text-gray-200">Quick Log</h2>
    <div class="grid grid-cols-2 gap-3">
      <a
        href="/log/insulin"
        class="flex min-h-[80px] flex-col items-center justify-center rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
      >
        <svg class="h-8 w-8 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
          />
        </svg>
        <span class="mt-2 text-sm font-medium text-gray-200">Insulin</span>
      </a>
      <a
        href="/log/meal"
        class="flex min-h-[80px] flex-col items-center justify-center rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
      >
        <svg class="h-8 w-8 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
          />
        </svg>
        <span class="mt-2 text-sm font-medium text-gray-200">Meal</span>
      </a>
    </div>
  </section>

  <!-- Today's Summary -->
  <section>
    <h2 class="mb-4 text-lg font-semibold text-gray-200">Today</h2>

    {#if eventsStore.loading}
      <div class="flex justify-center py-8">
        <div
          class="h-8 w-8 animate-spin rounded-full border-2 border-brand-accent border-t-transparent"
        ></div>
      </div>
    {:else if eventsStore.events.length === 0}
      <EmptyState
        title="No entries yet"
        description="Start tracking by logging your first insulin dose or meal."
      >
        {#snippet action()}
          <Button href="/log" variant="primary">Log Entry</Button>
        {/snippet}
      </EmptyState>
    {:else}
      <div class="grid grid-cols-3 gap-3">
        <div class="rounded-lg bg-gray-800 p-4 text-center">
          <p class="text-2xl font-bold text-blue-400">{todayStats.totalInsulin}</p>
          <p class="mt-1 text-xs text-gray-400">units insulin</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4 text-center">
          <p class="text-2xl font-bold text-green-400">{todayStats.totalCarbs}</p>
          <p class="mt-1 text-xs text-gray-400">g carbs</p>
        </div>
        <div class="rounded-lg bg-gray-800 p-4 text-center">
          <p class="text-2xl font-bold text-yellow-400">
            {todayStats.avgBSL !== null ? todayStats.avgBSL.toFixed(1) : '-'}
          </p>
          <p class="mt-1 text-xs text-gray-400">avg BSL</p>
        </div>
      </div>

      <!-- Recent Events -->
      <div class="mt-6">
        <h3 class="mb-3 text-sm font-medium text-gray-400">Recent entries</h3>
        <ul class="space-y-2">
          {#each eventsStore.events.slice(0, 5) as event (event.id)}
            <li class="flex items-center justify-between rounded-lg bg-gray-800/50 px-4 py-3">
              <div class="flex items-center gap-3">
                <span
                  class="flex h-8 w-8 items-center justify-center rounded-full {event.eventType ===
                  'insulin'
                    ? 'bg-blue-500/20 text-blue-400'
                    : event.eventType === 'meal'
                      ? 'bg-green-500/20 text-green-400'
                      : 'bg-yellow-500/20 text-yellow-400'}"
                >
                  {#if event.eventType === 'insulin'}
                    <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
                      />
                    </svg>
                  {:else if event.eventType === 'meal'}
                    <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
                      />
                    </svg>
                  {:else}
                    <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                      />
                    </svg>
                  {/if}
                </span>
                <div>
                  <p class="text-sm font-medium text-gray-200">
                    {event.eventType === 'insulin'
                      ? `${event.value} units`
                      : event.eventType === 'meal'
                        ? `${event.value}g carbs`
                        : `${event.value} mmol/L`}
                  </p>
                  <p class="text-xs text-gray-500">
                    {new Date(event.timestamp).toLocaleTimeString([], {
                      hour: '2-digit',
                      minute: '2-digit'
                    })}
                  </p>
                </div>
              </div>
            </li>
          {/each}
        </ul>
      </div>
    {/if}
  </section>
</div>
