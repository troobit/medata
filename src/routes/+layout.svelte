<script lang="ts">
  import '../app.css';
  import { AppShell } from '$lib/components/layout';
  import { settingsStore } from '$lib/stores';
  import { onMount } from 'svelte';
  import type { Snippet } from 'svelte';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();

  onMount(() => {
    // Load settings on app start
    settingsStore.load();

    // Register service worker
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/service-worker.js').catch((err) => {
        console.error('Service worker registration failed:', err);
      });
    }
  });
</script>

<svelte:head>
  <title>MeData</title>
  <meta name="description" content="Personal health data tracking for meals, insulin, and blood sugar" />
</svelte:head>

<AppShell>
  {@render children()}
</AppShell>
