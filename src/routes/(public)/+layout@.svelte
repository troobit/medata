<script lang="ts">
  import '../../app.css';
  import type { Snippet } from 'svelte';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();
</script>

<svelte:head>
  <title>MeData</title>
  <meta
    name="description"
    content="Personal health data tracking for meals, insulin, and blood sugar"
  />
</svelte:head>

<div class="min-h-screen bg-gray-900">
  {@render children()}
</div>
