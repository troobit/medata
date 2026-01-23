<script lang="ts">
  import { authStore } from '$lib/stores';
  import { Button, Logo } from '$lib/components/ui';
  import { startRegistration } from '@simplewebauthn/browser';

  let showBootstrap = $state(false);
  let bootstrapToken = $state('');
  let bootstrapLoading = $state(false);
  let bootstrapError = $state<string | null>(null);

  async function handleLogin() {
    const success = await authStore.login();
    // If login fails with NO_CREDENTIALS error, show bootstrap UI
    if (!success && authStore.error?.includes('No credentials registered')) {
      showBootstrap = true;
      authStore.clearError();
    }
  }

  async function handleBootstrap() {
    if (!bootstrapToken.trim()) {
      bootstrapError = 'Please enter the bootstrap token';
      return;
    }

    bootstrapLoading = true;
    bootstrapError = null;

    try {
      // Get bootstrap registration options
      const optionsResponse = await fetch('/api/auth/bootstrap/options', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bootstrapToken: bootstrapToken.trim() })
      });

      if (!optionsResponse.ok) {
        const error = await optionsResponse.json();
        throw new Error(error.error || 'Failed to get registration options');
      }

      const options = await optionsResponse.json();

      // Prompt for YubiKey registration
      const credential = await startRegistration({ optionsJSON: options });

      // Verify and complete bootstrap
      const verifyResponse = await fetch('/api/auth/bootstrap/verify', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          bootstrapToken: bootstrapToken.trim(),
          credential,
          friendlyName: 'Primary Hardware Key'
        })
      });

      if (!verifyResponse.ok) {
        const error = await verifyResponse.json();
        throw new Error(error.error || 'Failed to verify registration');
      }

      // Success - reload to update auth state
      window.location.reload();
    } catch (e) {
      if (e instanceof Error) {
        if (e.name === 'NotAllowedError') {
          bootstrapError = 'Registration was cancelled or timed out';
        } else {
          bootstrapError = e.message;
        }
      } else {
        bootstrapError = 'Registration failed';
      }
    } finally {
      bootstrapLoading = false;
    }
  }

  function cancelBootstrap() {
    showBootstrap = false;
    bootstrapToken = '';
    bootstrapError = null;
  }
</script>

<div class="flex min-h-screen flex-col items-center justify-center bg-gray-900 px-4">
  <div class="w-full max-w-sm space-y-8 text-center">
    <div class="space-y-2">
      <h1 class="text-3xl font-bold text-white">MeData</h1>
      <p class="text-gray-400">data tracking</p>
    </div>

    <div class="space-y-4">
      {#if showBootstrap}
        <!-- Bootstrap Flow: First-time credential enrollment -->
        <div class="rounded-lg border border-brand-accent/50 bg-gray-800/50 p-6">
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
              <path d="M12 2L2 7l10 5 10-5-10-5z" />
              <path d="M2 17l10 5 10-5" />
              <path d="M2 12l10 5 10-5" />
            </svg>
          </div>

          <div class="mb-4">
            <input
              type="password"
              bind:value={bootstrapToken}
              placeholder="token"
              class="w-full rounded-lg border border-gray-600 bg-gray-700 px-4 py-2 text-white placeholder-gray-400 focus:border-brand-accent focus:outline-none"
            />
          </div>

          <div class="flex gap-2">
            <Button
              variant="secondary"
              size="md"
              class="flex-1"
              onclick={cancelBootstrap}
              disabled={bootstrapLoading}
            >
              Cancel
            </Button>
            <Button
              variant="primary"
              size="md"
              class="flex-1"
              loading={bootstrapLoading}
              onclick={handleBootstrap}
            >
              Add Key
            </Button>
          </div>
        </div>

        {#if bootstrapError}
          <div
            class="rounded-lg border border-red-500/50 bg-red-500/10 p-4 text-sm text-red-400"
            role="alert"
          >
            <p>{bootstrapError}</p>
          </div>
        {/if}
      {:else}
        <!-- Normal Login Flow -->
        <div class="rounded-lg border border-gray-700 bg-gray-800/50 p-6">
          <Button
            variant="primary"
            size="lg"
            class="w-full"
            loading={authStore.loading}
            onclick={handleLogin}
          >
            <svg
              class="h-16 w-16 text-red-400"
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
            </svg></Button
          >
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
      {/if}
    </div>

    <p class="text-xs text-gray-500"><Logo /></p>
  </div>
</div>
