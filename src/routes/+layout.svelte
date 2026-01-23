<script lang="ts">
  import '../app.css';
  import { env } from '$env/dynamic/public';
  import { AuthGate } from '$lib/components/auth';
  import { AppShell } from '$lib/components/layout';
  import { Logo, StorageError } from '$lib/components/ui';
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

  // Favicon variant from build-time environment variable
  type LogoVariant = 'default' | 'colour' | 'contrast';
  const validVariants: LogoVariant[] = ['default', 'colour', 'contrast'];
  const envVariant = env.PUBLIC_LOGO_VARIANT;
  const faviconVariant: LogoVariant = validVariants.includes(envVariant as LogoVariant)
    ? (envVariant as LogoVariant)
    : 'default';

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
  <link rel="icon" type="image/svg+xml" href="/favicon-{faviconVariant}.svg" />
  <link rel="apple-touch-icon" href="/apple-touch-icon-{faviconVariant}.png" />
</svelte:head>

{#if !dbChecked}
  <div class="flex min-h-screen items-center justify-center bg-gray-900">
    <Logo animated size="splash" />
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
