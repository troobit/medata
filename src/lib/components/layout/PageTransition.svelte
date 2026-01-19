<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import type { Snippet } from 'svelte';
  import { navigationStore } from '$lib/stores/navigation.svelte';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();

  // Track navigation for direction
  $effect(() => {
    navigationStore.navigate($page.url.pathname);
  });

  // CSS class for slide direction
  let transitionClass = $derived.by(() => {
    switch (navigationStore.direction) {
      case 'left':
        return 'slide-left';
      case 'right':
        return 'slide-right';
      default:
        return '';
    }
  });
</script>

<div class="page-transition-wrapper {transitionClass}">
  {#key $page.url.pathname}
    <div class="page-content">
      {@render children()}
    </div>
  {/key}
</div>

<style>
  .page-transition-wrapper {
    position: relative;
    width: 100%;
    min-height: 100%;
  }

  .page-content {
    animation: fadeIn 0.2s ease-out;
  }

  .slide-left .page-content {
    animation: slideInFromRight 0.25s ease-out;
  }

  .slide-right .page-content {
    animation: slideInFromLeft 0.25s ease-out;
  }

  @keyframes fadeIn {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  @keyframes slideInFromRight {
    from {
      opacity: 0;
      transform: translateX(30px);
    }
    to {
      opacity: 1;
      transform: translateX(0);
    }
  }

  @keyframes slideInFromLeft {
    from {
      opacity: 0;
      transform: translateX(-30px);
    }
    to {
      opacity: 1;
      transform: translateX(0);
    }
  }
</style>
