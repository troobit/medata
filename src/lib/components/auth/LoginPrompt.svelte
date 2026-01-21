<script lang="ts">
  import { authStore } from '$lib/stores';
  import { Button } from '$lib/components/ui';

  async function handleLogin() {
    await authStore.login();
  }
</script>

<div class="flex min-h-screen flex-col items-center justify-center bg-gray-900 px-4">
  <div class="w-full max-w-sm space-y-8 text-center">
    <div class="space-y-2">
      <h1 class="text-3xl font-bold text-white">MeData</h1>
      <p class="text-gray-400">Personal health data tracking</p>
    </div>

    <div class="space-y-4">
      <div class="rounded-lg border border-gray-700 bg-gray-800/50 p-6">
        <div class="mb-4 flex justify-center">
          <svg
            class="h-16 w-16 text-brand-accent"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <circle cx="12" cy="16" r="1" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        </div>

        <p class="mb-6 text-sm text-gray-300">Insert your security key and tap to authenticate</p>

        <Button
          variant="primary"
          size="lg"
          class="w-full"
          loading={authStore.loading}
          onclick={handleLogin}
        >
          Authenticate with Security Key
        </Button>
      </div>

      {#if authStore.error}
        <div
          class="rounded-lg border border-red-500/50 bg-red-500/10 p-4 text-sm text-red-400"
          role="alert"
        >
          <p>{authStore.error}</p>
          <button
            class="mt-2 text-red-300 underline hover:text-red-200"
            onclick={() => authStore.clearError()}
          >
            Dismiss
          </button>
        </div>
      {/if}
    </div>

    <p class="text-xs text-gray-500">Requires a registered FIDO2 security key</p>
  </div>
</div>
