<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		children: Snippet;
	}

	let { children }: Props = $props();
</script>

<div class="min-h-screen bg-primary-background text-white">
	<header class="flex items-center gap-3 px-4 py-3 border-b border-white/10">
		<img src="/icon.svg" alt="MeData" class="h-10 w-10" />
		<h1 class="text-xl font-semibold text-brand-accent">MeData</h1>
	</header>

	<main class="px-4 py-6">
		{@render children()}
	</main>
</div>
