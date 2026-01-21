<script lang="ts">
  import '../app.css';
  import { AuthGate } from '$lib/components/auth';
  import { AppShell } from '$lib/components/layout';
  import { LoadingSpinner, StorageError } from '$lib/components/ui';
  import { checkDatabaseAvailability } from '$lib/db';
  import { authStore, settingsStore } from '$lib/stores';
  import { onMount } from 'svelte';
  import type { Snippet } from 'svelte';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();

  let dbError = $state<string | null>(null);
  let dbChecked = $state(false);

  onMount(async () => {
    // Check database availability before loading the app
    const error = await checkDatabaseAvailability();
    dbError = error;
    dbChecked = true;

    // Register service worker
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/service-worker.js').catch((err) => {
        console.error('Service worker registration failed:', err);
      });
    }
  });

  // Load settings once authenticated and DB is available
  $effect(() => {
    if (authStore.isAuthenticated && dbChecked && !dbError) {
      settingsStore.load();
    }
  });
</script>

<svelte:head>
  <title>MeData</title>
  <meta
    name="description"
    content="Personal health data tracking for meals, insulin, and blood sugar"
  />
</svelte:head>

{#if !dbChecked}
  <div class="flex min-h-screen items-center justify-center bg-gray-900">
    <LoadingSpinner size="lg" />
  </div>
{:else if dbError}
  <StorageError error={dbError} />
{:else}
  <AuthGate>
    <AppShell>
      {@render children()}
    </AppShell>
  </AuthGate>
{/if}
