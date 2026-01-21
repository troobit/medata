<script lang="ts">
  import { slide } from 'svelte/transition';
  import { Spring } from 'svelte/motion';
  import { getAnimationDuration } from '$lib/utils/motion.svelte';
  import type { Snippet } from 'svelte';

  interface Props {
    title: string;
    subtitle?: string;
    collapsed?: boolean;
    children: Snippet;
  }

  let { title, subtitle, collapsed = true, children }: Props = $props();

  // Track expansion state
  let localExpanded = $state<boolean | null>(null);
  const isExpanded = $derived(!collapsed);
  const expanded = $derived(localExpanded !== null ? localExpanded : isExpanded);

  function toggleExpanded() {
    localExpanded = !expanded;
  }

  // Spring animation for icon rotation
  const iconRotation = new Spring(0, {
    stiffness: 0.3,
    damping: 0.8
  });

  $effect(() => {
    iconRotation.set(expanded ? 180 : 0, {
      hard: getAnimationDuration(1) === 0
    });
  });
</script>

<section class="rounded-lg border border-gray-800 bg-gray-900/50">
  <header
    class="flex cursor-pointer items-center justify-between gap-4 px-4 py-3"
    onclick={toggleExpanded}
    role="button"
    tabindex="0"
    aria-expanded={expanded}
    onkeydown={(e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        toggleExpanded();
      }
    }}
  >
    <div class="flex-1">
      <h2 class="text-lg font-semibold text-gray-200">{title}</h2>
      {#if subtitle}
        <p class="mt-0.5 text-sm text-gray-400">{subtitle}</p>
      {/if}
    </div>
    <span
      class="inline-block text-gray-400 transition-colors"
      style="transform: rotate({iconRotation.current}deg)"
      aria-hidden="true"
    >
      <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </span>
  </header>

  {#if expanded}
    <div class="border-t border-gray-800 px-4 py-4" transition:slide={{ duration: getAnimationDuration(200) }}>
      {@render children()}
    </div>
  {/if}
</section>
