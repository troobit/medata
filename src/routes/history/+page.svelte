<script lang="ts">
  import { EmptyState, LoadingSpinner } from '$lib/components/ui';
  import { InsulinIcon, MealIcon, BSLIcon, AlcoholIcon } from '$lib/components/icons';
  import { eventsStore } from '$lib/stores';
  import { onMount } from 'svelte';
  import type { EventType, MealMetadata } from '$lib/types';

  let filter = $state<EventType | 'all'>('all');

  onMount(() => {
    eventsStore.loadRecent(50);
  });

  const filteredEvents = $derived(
    filter === 'all' ? eventsStore.events : eventsStore.events.filter((e) => e.eventType === filter)
  );

  // Group events by date - using array of tuples instead of Map for cleaner iteration
  const groupedEvents = $derived.by(() => {
    const groupMap: Record<string, typeof eventsStore.events> = {};

    for (const event of filteredEvents) {
      const date = new Date(event.timestamp).toLocaleDateString('en-AU', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      });

      if (!groupMap[date]) {
        groupMap[date] = [];
      }
      groupMap[date].push(event);
    }

    return Object.entries(groupMap);
  });

  function formatTime(date: Date): string {
    return new Date(date).toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  function getEventLabel(event: (typeof eventsStore.events)[0]): string {
    switch (event.eventType) {
      case 'insulin':
        return `${event.value} units ${(event.metadata as { type?: string }).type || ''}`;
      case 'meal': {
        const meta = event.metadata as MealMetadata;
        const parts: string[] = [];
        if (event.value > 0) parts.push(`${event.value}g carbs`);
        if (meta.alcoholUnits && meta.alcoholUnits > 0) {
          parts.push(`${meta.alcoholUnits} ${meta.alcoholUnits === 1 ? 'drink' : 'drinks'}`);
        }
        return parts.length > 0 ? parts.join(', ') : 'Logged';
      }
      case 'bsl':
        return `${event.value} ${(event.metadata as { unit?: string }).unit || 'mmol/L'}`;
      case 'exercise':
        return `${event.value} min`;
      default:
        return String(event.value);
    }
  }

  function hasAlcohol(event: (typeof eventsStore.events)[0]): boolean {
    if (event.eventType !== 'meal') return false;
    const meta = event.metadata as MealMetadata;
    return (meta.alcoholUnits ?? 0) > 0;
  }
</script>

<div class="px-4 py-6">
  <header class="mb-6">
    <h1 class="text-2xl font-bold text-white">History</h1>
  </header>

  <!-- Filter Tabs -->
  <div class="mb-6 flex gap-2 overflow-x-auto pb-2">
    {#each [{ value: 'all', label: 'All' }, { value: 'insulin', label: 'Insulin' }, { value: 'meal', label: 'Meals' }, { value: 'bsl', label: 'BSL' }] as option (option.value)}
      <button
        type="button"
        class="whitespace-nowrap rounded-full px-4 py-2 text-sm font-medium transition-colors {filter ===
        option.value
          ? 'bg-brand-accent text-gray-950'
          : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
        onclick={() => (filter = option.value as EventType | 'all')}
      >
        {option.label}
      </button>
    {/each}
  </div>

  <!-- Events List -->
  {#if eventsStore.loading}
    <div class="flex justify-center py-12">
      <LoadingSpinner size="lg" />
    </div>
  {:else if filteredEvents.length === 0}
    <EmptyState
      title="No entries found"
      description={filter === 'all'
        ? 'Start tracking by logging your first entry.'
        : `No ${filter} entries found.`}
    />
  {:else}
    <div class="space-y-6">
      {#each groupedEvents as [date, events] (date)}
        <div>
          <h2 class="mb-3 text-sm font-medium text-gray-400">{date}</h2>
          <ul class="space-y-2">
            {#each events as event (event.id)}
              <li class="flex items-center justify-between rounded-lg bg-gray-800/50 px-4 py-3">
                <div class="flex items-center gap-3">
                  <!-- Icon container - shows both meal and alcohol icons when alcohol is present -->
                  <div class="flex items-center gap-1">
                    <span
                      class="flex h-10 w-10 items-center justify-center rounded-full {event.eventType ===
                      'insulin'
                        ? 'bg-blue-500/20 text-blue-400'
                        : event.eventType === 'meal'
                          ? 'bg-green-500/20 text-green-400'
                          : event.eventType === 'bsl'
                            ? 'bg-yellow-500/20 text-yellow-400'
                            : 'bg-purple-500/20 text-purple-400'}"
                    >
                      {#if event.eventType === 'insulin'}
                        <InsulinIcon class="h-5 w-5" />
                      {:else if event.eventType === 'meal'}
                        <MealIcon class="h-5 w-5" />
                      {:else if event.eventType === 'bsl'}
                        <BSLIcon class="h-5 w-5" />
                      {:else}
                        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M13 10V3L4 14h7v7l9-11h-7z"
                          />
                        </svg>
                      {/if}
                    </span>
                    {#if hasAlcohol(event)}
                      <span
                        class="flex h-8 w-8 items-center justify-center rounded-full bg-amber-500/20 text-amber-400"
                      >
                        <AlcoholIcon class="h-4 w-4" />
                      </span>
                    {/if}
                  </div>
                  <div>
                    <p class="font-medium text-gray-200">
                      {getEventLabel(event)}
                    </p>
                    <p class="text-sm text-gray-500">
                      {formatTime(event.timestamp)}
                      {#if event.eventType === 'meal' && (event.metadata as { description?: string }).description}
                        <span class="ml-2 text-gray-400"
                          >- {(event.metadata as { description?: string }).description}</span
                        >
                      {/if}
                    </p>
                  </div>
                </div>
              </li>
            {/each}
          </ul>
        </div>
      {/each}
    </div>
  {/if}
</div>
