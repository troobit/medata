<script lang="ts">
  import type { Snippet } from 'svelte';
  import BottomNav from './BottomNav.svelte';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();
</script>

<div class="flex min-h-dvh flex-col bg-gray-950">
  <!-- Main content area with bottom padding for nav -->
  <main class="flex-1 pb-20">
    {@render children()}
  </main>

  <!-- Fixed bottom navigation -->
  <BottomNav />
</div>
