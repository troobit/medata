<script lang="ts">
	/**
	 * ImagePreview component for displaying captured image before AI analysis.
	 * Req 1.3: Display preview before AI analysis
	 * Req 1.4: Allow retake if unsatisfactory
	 */

	interface Props {
		image: Blob;
		onConfirm: () => void;
		onRetake: () => void;
		isProcessing?: boolean;
	}

	let { image, onConfirm, onRetake, isProcessing = false }: Props = $props();

	let imageUrl = $derived(URL.createObjectURL(image));

	// Cleanup object URL on unmount or when image changes
	$effect(() => {
		return () => {
			URL.revokeObjectURL(imageUrl);
		};
	});
</script>

<div class="flex flex-col gap-4">
	<!-- Image preview -->
	<div class="overflow-hidden rounded-lg bg-black">
		<img src={imageUrl} alt="Food preview" class="w-full object-contain max-h-[60vh]" />
	</div>

	<!-- Action buttons -->
	<div class="flex gap-3">
		<button
			onclick={onConfirm}
			disabled={isProcessing}
			class="flex-1 rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
		>
			{#if isProcessing}
				Analysing...
			{:else}
				Confirm
			{/if}
		</button>
		<button
			onclick={onRetake}
			disabled={isProcessing}
			class="rounded-lg bg-white/10 px-6 py-4 text-lg font-semibold text-white min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
		>
			Retake
		</button>
	</div>
</div>
