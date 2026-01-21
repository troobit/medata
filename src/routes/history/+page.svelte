<script lang="ts">
  import { EmptyState, LoadingSpinner } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';
  import { onMount } from 'svelte';
  import type { EventType, MealMetadata, AlcoholType } from '$lib/types';

  let filter = $state<EventType | 'all'>('all');

  onMount(() => {
    eventsStore.loadRecent(50);
  });

  const filteredEvents = $derived(
    filter === 'all' ? eventsStore.events : eventsStore.events.filter((e) => e.eventType === filter)
  );

  // Group events by date
  const groupedEvents = $derived(() => {
    const groups: Map<string, typeof eventsStore.events> = new Map();

    for (const event of filteredEvents) {
      const date = new Date(event.timestamp).toLocaleDateString('en-AU', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      });

      if (!groups.has(date)) {
        groups.set(date, []);
      }
      groups.get(date)!.push(event);
    }

    return groups;
  });

  function formatTime(date: Date): string {
    return new Date(date).toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit'
    });
  }

  // Check if a meal event has alcohol
  function hasAlcohol(event: (typeof eventsStore.events)[0]): boolean {
    if (event.eventType !== 'meal') return false;
    const metadata = event.metadata as MealMetadata;
    return (metadata.alcoholUnits ?? 0) > 0;
  }

  // Get alcohol info from meal metadata
  function getAlcoholInfo(event: (typeof eventsStore.events)[0]): { units: number; type?: AlcoholType } | null {
    if (event.eventType !== 'meal') return null;
    const metadata = event.metadata as MealMetadata;
    if (!metadata.alcoholUnits || metadata.alcoholUnits <= 0) return null;
    return { units: metadata.alcoholUnits, type: metadata.alcoholType };
  }

  // Calculate alcohol decay (rough estimate based on ~1 unit per hour)
  function getAlcoholDecayPercent(event: (typeof eventsStore.events)[0]): number {
    const alcoholInfo = getAlcoholInfo(event);
    if (!alcoholInfo) return 100;

    const hoursElapsed = (Date.now() - new Date(event.timestamp).getTime()) / (1000 * 60 * 60);
    const unitsRemaining = Math.max(0, alcoholInfo.units - hoursElapsed);
    const percentRemaining = (unitsRemaining / alcoholInfo.units) * 100;
    return Math.round(percentRemaining);
  }

  // Format alcohol type for display
  function formatAlcoholType(type?: AlcoholType): string {
    if (!type) return '';
    const labels: Record<AlcoholType, string> = {
      beer: 'Beer',
      wine: 'Wine',
      spirit: 'Spirit',
      mixed: 'Cocktail'
    };
    return labels[type] || type;
  }

  function getEventLabel(event: (typeof eventsStore.events)[0]): string {
    switch (event.eventType) {
      case 'insulin':
        return `${event.value} units ${(event.metadata as { type?: string }).type || ''}`;
      case 'meal': {
        const metadata = event.metadata as MealMetadata;
        const alcoholInfo = getAlcoholInfo(event);
        if (alcoholInfo && event.value === 0) {
          // Alcohol-only entry
          return `${alcoholInfo.units} units alcohol`;
        } else if (alcoholInfo) {
          // Mixed entry
          return `${event.value}g carbs + ${alcoholInfo.units}u`;
        }
        return `${event.value}g carbs`;
      }
      case 'bsl':
        return `${event.value} ${(event.metadata as { unit?: string }).unit || 'mmol/L'}`;
      case 'exercise':
        return `${event.value} min`;
      default:
        return String(event.value);
    }
  }
</script>

<div class="px-4 py-6">
  <header class="mb-6">
    <h1 class="text-2xl font-bold text-white">History</h1>
  </header>

  <!-- Filter Tabs -->
  <div class="mb-6 flex gap-2 overflow-x-auto pb-2">
    {#each [{ value: 'all', label: 'All' }, { value: 'insulin', label: 'Insulin' }, { value: 'meal', label: 'Meals' }, { value: 'bsl', label: 'BSL' }] as option}
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
      {#each [...groupedEvents().entries()] as [date, events]}
        <div>
          <h2 class="mb-3 text-sm font-medium text-gray-400">{date}</h2>
          <ul class="space-y-2">
            {#each events as event}
              <li class="flex items-center justify-between rounded-lg bg-gray-800/50 px-4 py-3">
                <div class="flex items-center gap-3">
                  <span
                    class="relative flex h-10 w-10 items-center justify-center rounded-full {event.eventType ===
                    'insulin'
                      ? 'bg-blue-500/20 text-blue-400'
                      : event.eventType === 'meal'
                        ? hasAlcohol(event)
                          ? 'bg-amber-500/20 text-amber-400'
                          : 'bg-green-500/20 text-green-400'
                        : event.eventType === 'bsl'
                          ? 'bg-yellow-500/20 text-yellow-400'
                          : 'bg-purple-500/20 text-purple-400'}"
                  >
                    {#if event.eventType === 'insulin'}
                      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
                        />
                      </svg>
                    {:else if event.eventType === 'meal'}
                      {#if hasAlcohol(event)}
                        <!-- Alcohol/drink icon -->
                        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                          />
                        </svg>
                      {:else}
                        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
                          />
                        </svg>
                      {/if}
                    {:else if event.eventType === 'bsl'}
                      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                        />
                      </svg>
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
                  <div class="flex-1">
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
                <!-- Alcohol decay indicator -->
                {#if hasAlcohol(event)}
                  {@const decayPercent = getAlcoholDecayPercent(event)}
                  {@const alcoholInfo = getAlcoholInfo(event)}
                  <div class="flex flex-col items-end gap-1">
                    {#if decayPercent > 0}
                      <div class="flex items-center gap-1.5" title="Alcohol still processing">
                        <div class="h-1.5 w-12 overflow-hidden rounded-full bg-gray-700">
                          <div
                            class="h-full rounded-full bg-amber-500 transition-all duration-500"
                            style="width: {decayPercent}%"
                          ></div>
                        </div>
                        <span class="text-xs text-amber-400">{decayPercent}%</span>
                      </div>
                    {:else}
                      <span class="text-xs text-gray-500">Processed</span>
                    {/if}
                    {#if alcoholInfo?.type}
                      <span class="text-xs text-gray-500">{formatAlcoholType(alcoholInfo.type)}</span>
                    {/if}
                  </div>
                {/if}
              </li>
            {/each}
          </ul>
        </div>
      {/each}
    </div>
  {/if}
</div>
