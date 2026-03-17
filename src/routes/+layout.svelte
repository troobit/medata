<script lang="ts">
	import '../app.css';
	import AppShell from '$lib/components/AppShell.svelte';
	import { ToastContainer } from '$lib/components/index.js';

	let { children } = $props();
</script>

<AppShell>
	{@render children()}
</AppShell>

<ToastContainer />
