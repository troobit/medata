<script lang="ts">
	/**
	 * Container component for rendering global toast notifications.
	 * Connects to the toast store and renders all active toasts.
	 */
	import { toastStore } from '$lib/stores/index.js';
	import Toast from './Toast.svelte';
</script>

{#each toastStore.toasts as toast (toast.id)}
	<Toast
		message={toast.message}
		type={toast.type}
		duration={toast.duration}
		onDismiss={() => toastStore.dismiss(toast.id)}
	/>
{/each}
