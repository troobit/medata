<script lang="ts">
  import { goto } from '$app/navigation';
  import { Button, Input } from '$lib/components/ui';
  import { eventsStore } from '$lib/stores';
  import type { ExerciseIntensity, ExerciseCategory, ExerciseMetadata } from '$lib/types';

  let duration = $state(30);
  let intensity = $state<ExerciseIntensity>('moderate');
  let category = $state<ExerciseCategory>('other');
  let exerciseType = $state('');
  let caloriesBurned = $state<number | undefined>(undefined);
  let heartRateAvg = $state<number | undefined>(undefined);
  let distanceKm = $state<number | undefined>(undefined);
  let saving = $state(false);
  let showAdvanced = $state(false);

  const categories: Array<{ value: ExerciseCategory; label: string; icon: string }> = [
    { value: 'walking', label: 'Walking', icon: '🚶' },
    { value: 'running', label: 'Running', icon: '🏃' },
    { value: 'cycling', label: 'Cycling', icon: '🚴' },
    { value: 'swimming', label: 'Swimming', icon: '🏊' },
    { value: 'weights', label: 'Weights', icon: '🏋️' },
    { value: 'hiit', label: 'HIIT', icon: '⚡' },
    { value: 'yoga', label: 'Yoga', icon: '🧘' },
    { value: 'sports', label: 'Sports', icon: '⚽' },
    { value: 'other', label: 'Other', icon: '💪' }
  ];

  const quickDurations = [15, 30, 45, 60, 90];

  function adjustDuration(amount: number) {
    const newValue = duration + amount;
    if (newValue >= 5 && newValue <= 300) {
      duration = newValue;
    }
  }

  async function save() {
    if (duration <= 0) return;

    saving = true;
    try {
      const metadata: Partial<ExerciseMetadata> = {
        category,
        exerciseType: exerciseType || undefined,
        caloriesBurned: caloriesBurned || undefined,
        heartRateAvg: heartRateAvg || undefined,
        distanceKm: distanceKm || undefined,
        source: 'manual'
      };

      await eventsStore.logExercise(duration, intensity, metadata);
      goto('/');
    } catch {
      // Error is shown via store
    } finally {
      saving = false;
    }
  }

  // Get intensity color class
  function getIntensityColor(i: ExerciseIntensity): string {
    switch (i) {
      case 'low':
        return 'bg-green-600';
      case 'moderate':
        return 'bg-yellow-600';
      case 'high':
        return 'bg-red-600';
    }
  }
</script>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <header class="mb-8">
    <a href="/log" class="mb-4 inline-flex items-center text-gray-400 hover:text-gray-200">
      <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back
    </a>
    <h1 class="text-2xl font-bold text-white">Log Exercise</h1>
  </header>

  <div class="flex flex-1 flex-col">
    <!-- Exercise Category -->
    <fieldset class="mb-6">
      <legend class="mb-2 block text-sm font-medium text-gray-400">Activity</legend>
      <div class="grid grid-cols-3 gap-2">
        {#each categories as cat}
          <button
            type="button"
            class="flex flex-col items-center rounded-lg px-3 py-3 text-center transition-colors {category ===
            cat.value
              ? 'bg-brand-accent text-white'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (category = cat.value)}
          >
            <span class="mb-1 text-xl">{cat.icon}</span>
            <span class="text-xs font-medium">{cat.label}</span>
          </button>
        {/each}
      </div>
    </fieldset>

    <!-- Intensity Toggle -->
    <fieldset class="mb-6">
      <legend class="mb-2 block text-sm font-medium text-gray-400">Intensity</legend>
      <div class="grid grid-cols-3 gap-2">
        <button
          type="button"
          class="rounded-lg px-4 py-3 text-center font-medium transition-colors {intensity === 'low'
            ? 'bg-green-600 text-white'
            : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
          onclick={() => (intensity = 'low')}
        >
          Low
        </button>
        <button
          type="button"
          class="rounded-lg px-4 py-3 text-center font-medium transition-colors {intensity ===
          'moderate'
            ? 'bg-yellow-600 text-white'
            : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
          onclick={() => (intensity = 'moderate')}
        >
          Moderate
        </button>
        <button
          type="button"
          class="rounded-lg px-4 py-3 text-center font-medium transition-colors {intensity === 'high'
            ? 'bg-red-600 text-white'
            : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
          onclick={() => (intensity = 'high')}
        >
          High
        </button>
      </div>
    </fieldset>

    <!-- Duration Input -->
    <div class="mb-6">
      <label for="duration-input" class="mb-2 block text-sm font-medium text-gray-400"
        >Duration</label
      >
      <div class="flex items-center justify-center gap-3">
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustDuration(-15)}
          disabled={duration < 20}
          aria-label="Decrease duration by 15"
        >
          -15
        </button>
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustDuration(-5)}
          disabled={duration <= 5}
          aria-label="Decrease duration by 5"
        >
          -5
        </button>
        <div class="w-24 text-center">
          <input
            id="duration-input"
            type="number"
            bind:value={duration}
            min="5"
            max="300"
            class="w-full bg-transparent text-center text-5xl font-bold text-white focus:outline-none"
            aria-describedby="duration-label"
          />
          <span id="duration-label" class="text-sm text-gray-400">minutes</span>
        </div>
        <button
          type="button"
          class="flex h-14 w-14 items-center justify-center rounded-full bg-gray-800 text-2xl text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustDuration(5)}
          disabled={duration >= 295}
          aria-label="Increase duration by 5"
        >
          +5
        </button>
        <button
          type="button"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800 text-lg font-medium text-gray-300 transition-colors hover:bg-gray-700 active:bg-gray-600 disabled:opacity-40"
          onclick={() => adjustDuration(15)}
          disabled={duration > 285}
          aria-label="Increase duration by 15"
        >
          +15
        </button>
      </div>
    </div>

    <!-- Quick Duration Select -->
    <fieldset class="mb-6">
      <legend class="mb-2 block text-sm font-medium text-gray-400">Quick select</legend>
      <div class="flex flex-wrap gap-2">
        {#each quickDurations as value}
          <button
            type="button"
            class="rounded-full px-4 py-2 text-sm font-medium transition-colors {duration === value
              ? 'bg-brand-accent text-white'
              : 'bg-gray-800 text-gray-300 hover:bg-gray-700'}"
            onclick={() => (duration = value)}
          >
            {value} min
          </button>
        {/each}
      </div>
    </fieldset>

    <!-- Advanced Options Toggle -->
    <button
      type="button"
      class="mb-4 text-left text-sm text-gray-400 hover:text-gray-200"
      onclick={() => (showAdvanced = !showAdvanced)}
    >
      {showAdvanced ? '▼' : '▶'} Advanced options
    </button>

    <!-- Advanced Options -->
    {#if showAdvanced}
      <div class="mb-6 space-y-4 rounded-lg border border-gray-800 bg-gray-900/30 p-4">
        <Input type="text" label="Exercise name (optional)" bind:value={exerciseType} placeholder="e.g., Morning jog" />

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label for="calories" class="mb-2 block text-sm font-medium text-gray-400">Calories burned</label>
            <input
              id="calories"
              type="number"
              bind:value={caloriesBurned}
              placeholder="kcal"
              class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
            />
          </div>
          <div>
            <label for="heartrate" class="mb-2 block text-sm font-medium text-gray-400">Avg heart rate</label>
            <input
              id="heartrate"
              type="number"
              bind:value={heartRateAvg}
              placeholder="bpm"
              class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
            />
          </div>
        </div>

        {#if category === 'walking' || category === 'running' || category === 'cycling'}
          <div>
            <label for="distance" class="mb-2 block text-sm font-medium text-gray-400">Distance (km)</label>
            <input
              id="distance"
              type="number"
              bind:value={distanceKm}
              placeholder="km"
              class="w-full rounded-lg border border-gray-700 bg-gray-800 px-4 py-3 text-white focus:border-brand-accent focus:outline-none focus:ring-2 focus:ring-brand-accent/30"
            />
          </div>
        {/if}
      </div>
    {/if}

    <!-- Spacer -->
    <div class="flex-1"></div>

    <!-- Error Display -->
    {#if eventsStore.error}
      <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
        {eventsStore.error}
      </div>
    {/if}

    <!-- Summary and Save -->
    <div class="space-y-4">
      <div class="rounded-lg bg-gray-800/50 p-4">
        <div class="flex items-center justify-between">
          <span class="text-gray-400">Activity</span>
          <span class="font-medium text-white">
            {categories.find((c) => c.value === category)?.icon}
            {categories.find((c) => c.value === category)?.label}
          </span>
        </div>
        <div class="mt-2 flex items-center justify-between">
          <span class="text-gray-400">Duration</span>
          <span class="font-medium text-white">{duration} minutes</span>
        </div>
        <div class="mt-2 flex items-center justify-between">
          <span class="text-gray-400">Intensity</span>
          <span class="flex items-center gap-2 font-medium text-white">
            <span class="h-2 w-2 rounded-full {getIntensityColor(intensity)}"></span>
            {intensity.charAt(0).toUpperCase() + intensity.slice(1)}
          </span>
        </div>
      </div>

      <Button
        variant="primary"
        size="lg"
        class="w-full"
        onclick={save}
        disabled={duration <= 0}
        loading={saving}
      >
        Log Exercise
      </Button>
    </div>
  </div>
</div>
