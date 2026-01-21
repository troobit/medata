<script lang="ts">
  import type { Snippet } from 'svelte';
  import { onMount } from 'svelte';
  import { authStore } from '$lib/stores';
  import { LoadingSpinner } from '$lib/components/ui';
  import LoginPrompt from './LoginPrompt.svelte';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();

  onMount(() => {
    authStore.checkSession();
  });
</script>

{#if authStore.isChecking}
  <div class="flex min-h-screen items-center justify-center bg-gray-900">
    <LoadingSpinner size="lg" />
  </div>
{:else if authStore.isAuthenticated}
  {@render children()}
{:else}
  <LoginPrompt />
{/if}
