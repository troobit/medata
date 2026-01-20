<script lang="ts">
  import { InsulinIcon, MealIcon, BSLIcon } from '$lib/components/icons';
</script>

<div class="px-4 py-6">
  <header class="mb-8">
    <h1 class="text-2xl font-bold text-white">Log Entry</h1>
    <p class="mt-1 text-gray-400">Choose what to log</p>
  </header>

  <div class="space-y-3">
    <a
      href="/log/insulin"
      class="flex items-center gap-4 rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
    >
      <span class="flex h-12 w-12 items-center justify-center rounded-full bg-blue-500/20">
        <InsulinIcon class="h-6 w-6 text-blue-400" />
      </span>
      <div class="flex-1">
        <h2 class="text-lg font-medium text-gray-200">Insulin</h2>
        <p class="text-sm text-gray-400">Log bolus or basal dose</p>
      </div>
      <svg class="h-5 w-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </a>

    <a
      href="/log/meal"
      class="flex items-center gap-4 rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
    >
      <span class="flex h-12 w-12 items-center justify-center rounded-full bg-green-500/20">
        <MealIcon class="h-6 w-6 text-green-400" />
      </span>
      <div class="flex-1">
        <h2 class="text-lg font-medium text-gray-200">Meal</h2>
        <p class="text-sm text-gray-400">Log food with macros</p>
      </div>
      <svg class="h-5 w-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </a>

    <a
      href="/log/bsl"
      class="flex items-center gap-4 rounded-xl bg-gray-800 p-4 transition-colors hover:bg-gray-700"
    >
      <span class="flex h-12 w-12 items-center justify-center rounded-full bg-yellow-500/20">
        <BSLIcon class="h-6 w-6 text-yellow-400" />
      </span>
      <div class="flex-1">
        <h2 class="text-lg font-medium text-gray-200">Blood Sugar</h2>
        <p class="text-sm text-gray-400">Log BSL reading</p>
      </div>
      <svg class="h-5 w-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </a>
  </div>

  <!-- Import Link -->
  <div class="mt-8 text-center">
    <a href="/import" class="text-sm text-gray-500 hover:text-gray-400">
      Import data from CGM apps or CSV →
    </a>
  </div>
</div>
