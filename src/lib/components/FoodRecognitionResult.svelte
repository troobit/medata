<script lang="ts">
	/**
	 * FoodRecognitionResult component for displaying AI recognition results.
	 * Req 2.2: Display itemised list with macros
	 * Req 2.3: Show confidence score for each item
	 * Req 2.4: Show all results regardless of confidence
	 * Req 2.5: Calculate and display aggregate totals
	 */
	import type { RecognisedFoodItem, MacroData } from '$lib/types/index.js';

	interface Props {
		items: RecognisedFoodItem[];
		totalMacros: MacroData;
		confidence: number;
		provider: string;
		processingTimeMs: number;
		onConfirm: (items: RecognisedFoodItem[]) => void;
		onRetry?: () => void;
		onManualEntry?: () => void;
	}

	let {
		items,
		totalMacros,
		confidence,
		provider,
		processingTimeMs,
		onConfirm,
		onRetry,
		onManualEntry
	}: Props = $props();

	/**
	 * Format confidence as a percentage.
	 */
	function formatConfidence(value: number): string {
		return `${Math.round(value * 100)}%`;
	}

	/**
	 * Get confidence badge colour based on value.
	 */
	function getConfidenceColour(value: number): string {
		if (value >= 0.8) return 'bg-green-600';
		if (value >= 0.6) return 'bg-yellow-600';
		return 'bg-red-600';
	}

	function handleConfirm() {
		onConfirm(items);
	}
</script>

<div class="flex flex-col gap-4">
	<!-- Header with overall confidence -->
	<div class="flex items-center justify-between">
		<h2 class="text-lg font-semibold">Recognition Results</h2>
		<div class="flex items-center gap-2 text-sm text-white/70">
			<span class="rounded px-2 py-0.5 {getConfidenceColour(confidence)}">
				{formatConfidence(confidence)}
			</span>
			<span>{provider}</span>
		</div>
	</div>

	<!-- Items list -->
	<div class="flex flex-col gap-2">
		{#each items as item, index (index)}
			<div class="rounded-lg bg-white/5 p-3">
				<div class="flex items-start justify-between gap-2">
					<div class="flex-1">
						<div class="flex items-center gap-2">
							<span class="font-medium">{item.name}</span>
							<span class="rounded px-1.5 py-0.5 text-xs {getConfidenceColour(item.confidence)}">
								{formatConfidence(item.confidence)}
							</span>
						</div>
						<div class="mt-1 text-sm text-white/70">
							{item.quantity} {item.unit}
						</div>
					</div>
				</div>
				<div class="mt-2 flex gap-4 text-sm">
					<div>
						<span class="text-white/50">Carbs</span>
						<span class="ml-1 font-medium text-brand-accent">{item.carbs}g</span>
					</div>
					<div>
						<span class="text-white/50">Protein</span>
						<span class="ml-1 font-medium">{item.protein}g</span>
					</div>
					<div>
						<span class="text-white/50">Fat</span>
						<span class="ml-1 font-medium">{item.fat}g</span>
					</div>
				</div>
			</div>
		{/each}
	</div>

	<!-- Totals -->
	<div class="rounded-lg bg-white/10 p-4">
		<div class="text-sm font-medium text-white/70 mb-2">Total Macros</div>
		<div class="flex gap-6">
			<div>
				<span class="text-white/50">Carbs</span>
				<span class="ml-1 text-xl font-bold text-brand-accent">{totalMacros.carbs}g</span>
			</div>
			<div>
				<span class="text-white/50">Protein</span>
				<span class="ml-1 text-xl font-bold">{totalMacros.protein}g</span>
			</div>
			<div>
				<span class="text-white/50">Fat</span>
				<span class="ml-1 text-xl font-bold">{totalMacros.fat}g</span>
			</div>
		</div>
	</div>

	<!-- Processing info -->
	<div class="text-xs text-white/40 text-center">
		Processed in {(processingTimeMs / 1000).toFixed(1)}s
	</div>

	<!-- Action buttons -->
	<div class="flex flex-col gap-2">
		<button
			onclick={handleConfirm}
			class="w-full rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px]"
		>
			Use These Results
		</button>
		<div class="flex gap-2">
			{#if onRetry}
				<button
					onclick={onRetry}
					class="flex-1 rounded-lg bg-white/10 py-3 text-base font-medium text-white min-h-[44px]"
				>
					Try Again
				</button>
			{/if}
			{#if onManualEntry}
				<button
					onclick={onManualEntry}
					class="flex-1 rounded-lg border border-white/20 py-3 text-base font-medium text-white/70 min-h-[44px]"
				>
					Enter Manually
				</button>
			{/if}
		</div>
	</div>
</div>
