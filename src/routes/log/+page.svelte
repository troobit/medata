<script lang="ts">
  // Log entry hub - directs to specific entry types
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
        <svg class="h-6 w-6 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"
          />
        </svg>
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
        <svg class="h-6 w-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
          />
        </svg>
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
        <svg class="h-6 w-6 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
          />
        </svg>
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
