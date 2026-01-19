<script lang="ts">
  import { Button, EmptyState } from '$lib/components/ui';
  import { InsulinIcon, MealIcon, BSLIcon } from '$lib/components/icons';
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
  <header class="mb-8 flex items-center gap-3">
    <svg class="h-10 w-10" viewBox="0 0 128 128" aria-label="MeData logo">
      <path
        fill="none"
        stroke="currentColor"
        stroke-width="16"
        stroke-linecap="round"
        stroke-linejoin="round"
        class="text-brand-accent"
        d="M 24,24 C 130,24 130,104 24,104 L 24,64 M 104,64 L 104,104 M 64,64 L 64,64"
      />
    </svg>
    <div>
      <h1 class="text-2xl font-bold text-white">MeData</h1>
      <p class="text-sm text-gray-400">My Data</p>
    </div>
  </header>

  <!-- Quick Actions -->
  <section class="mb-8">
    <h2 class="mb-4 text-lg font-semibold text-gray-200">Quick Log</h2>
    <div class="grid grid-cols-2 gap-3">
      <a
        href="/log/insulin"
        class="flex min-h-[80px] flex-col items-center justify-center rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
      >
        <InsulinIcon class="h-8 w-8 text-blue-400" />
        <span class="mt-2 text-sm font-medium text-gray-200">Insulin</span>
      </a>
      <a
        href="/log/meal"
        class="flex min-h-[80px] flex-col items-center justify-center rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
      >
        <MealIcon class="h-8 w-8 text-green-400" />
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
                    <InsulinIcon class="h-4 w-4" />
                  {:else if event.eventType === 'meal'}
                    <MealIcon class="h-4 w-4" />
                  {:else}
                    <BSLIcon class="h-4 w-4" />
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
