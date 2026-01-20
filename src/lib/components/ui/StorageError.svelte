<script lang="ts">
  interface Props {
    error: string;
  }

  let { error }: Props = $props();
</script>

<div class="flex min-h-screen flex-col items-center justify-center bg-gray-900 p-6 text-center">
  <div class="mb-6 rounded-full bg-red-500/20 p-4">
    <svg class="h-12 w-12 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
      />
    </svg>
  </div>

  <h1 class="mb-2 text-xl font-bold text-white">Storage Unavailable</h1>

  <p class="mb-6 max-w-md text-gray-400">
    MeData needs access to your browser's storage to save your data. This feature appears to be
    blocked or unavailable.
  </p>

  <div class="mb-6 max-w-md rounded-lg bg-gray-800 p-4 text-left text-sm text-gray-300">
    <p class="mb-2 font-medium text-gray-200">Common causes:</p>
    <ul class="list-inside list-disc space-y-1">
      <li>Private/Incognito browsing mode (especially Safari)</li>
      <li>Browser settings blocking site data</li>
      <li>Device storage is full</li>
      <li>Third-party cookie blocking enabled</li>
    </ul>
  </div>

  <div class="mb-6 max-w-md rounded-lg bg-gray-800/50 p-3 text-left text-xs text-gray-500">
    <p class="font-mono">{error}</p>
  </div>

  <div class="flex flex-col gap-3">
    <button
      type="button"
      class="rounded-lg bg-brand-accent px-6 py-3 font-medium text-gray-900 transition-colors hover:bg-brand-accent/90"
      onclick={() => window.location.reload()}
    >
      Try Again
    </button>
    <a
      href="https://github.com/your-repo/medata#troubleshooting"
      target="_blank"
      rel="noopener noreferrer"
      class="text-sm text-gray-400 hover:text-gray-200"
    >
      View troubleshooting guide →
    </a>
  </div>
</div>
