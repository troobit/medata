<script lang="ts">
	/**
	 * MealDetail component for displaying full meal details.
	 * Req 8.3: Expand to view full details
	 * Req 8.6: Display associated photo if available
	 * D-DES-004: Show placeholder on image 404
	 */
	import type { Meal } from '$lib/types/index.js';

	interface Props {
		meal: Meal;
		onEdit: () => void;
		onDelete: () => void;
		onClose: () => void;
	}

	let { meal, onEdit, onDelete, onClose }: Props = $props();

	// Track image loading state
	let imageError = $state(false);

	/**
	 * Format timestamp for display.
	 */
	function formatDateTime(timestamp: number): string {
		const date = new Date(timestamp);
		return date.toLocaleDateString('en-IE', {
			weekday: 'long',
			day: 'numeric',
			month: 'long',
			year: 'numeric',
			hour: '2-digit',
			minute: '2-digit',
			hour12: false
		});
	}

	/**
	 * Get data source label for display.
	 */
	function getSourceLabel(source: Meal['source']): string {
		switch (source) {
			case 'ai_image':
				return 'Photo capture';
			case 'manual':
				return 'Manual entry';
			case 'preset':
				return 'Preset';
			default:
				return 'Unknown';
		}
	}

	/**
	 * Handle image load error.
	 */
	function handleImageError() {
		imageError = true;
	}
</script>

<div class="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
	<!-- Backdrop -->
	<button class="absolute inset-0 bg-black/80" onclick={onClose} aria-label="Close"></button>

	<!-- Modal content -->
	<div
		class="relative w-full max-w-lg bg-gray-900 rounded-t-2xl sm:rounded-2xl max-h-[90vh] overflow-y-auto"
	>
		<!-- Header with close button -->
		<div class="sticky top-0 bg-gray-900 border-b border-white/10 p-4 flex items-center gap-3">
			<button
				onclick={onClose}
				class="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-lg bg-white/10 text-white hover:bg-white/20"
				aria-label="Close"
			>
				<svg
					xmlns="http://www.w3.org/2000/svg"
					class="h-5 w-5"
					viewBox="0 0 20 20"
					fill="currentColor"
				>
					<path
						fill-rule="evenodd"
						d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
						clip-rule="evenodd"
					/>
				</svg>
			</button>
			<h2 class="text-lg font-semibold text-white flex-1">Meal Details</h2>
		</div>

		<div class="p-4 space-y-6">
			<!-- Image (if available) -->
			{#if meal.imageUrl && !imageError}
				<div class="aspect-video rounded-xl overflow-hidden bg-white/5">
					<img
						src={meal.imageUrl}
						alt="Meal"
						class="w-full h-full object-cover"
						onerror={handleImageError}
					/>
				</div>
			{:else if meal.imageUrl && imageError}
				<!-- D-DES-004: Placeholder on image 404 -->
				<div
					class="aspect-video rounded-xl overflow-hidden bg-white/5 flex items-center justify-center"
				>
					<div class="text-center text-white/30">
						<svg
							xmlns="http://www.w3.org/2000/svg"
							class="h-12 w-12 mx-auto mb-2"
							fill="none"
							viewBox="0 0 24 24"
							stroke="currentColor"
						>
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="1.5"
								d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
							/>
						</svg>
						<p class="text-sm">Image not available</p>
					</div>
				</div>
			{/if}

			<!-- Timestamp and source -->
			<div class="space-y-1">
				<p class="text-white/80">{formatDateTime(meal.timestamp)}</p>
				<p class="text-white/50 text-sm">{getSourceLabel(meal.source)}</p>
			</div>

			<!-- Macro totals - prominent -->
			<div class="grid grid-cols-3 gap-4 p-4 bg-white/5 rounded-xl">
				<div class="text-center">
					<div class="text-2xl font-bold text-brand-accent">{meal.totalCarbs}g</div>
					<div class="text-white/50 text-sm">Carbs</div>
				</div>
				<div class="text-center">
					<div class="text-2xl font-bold text-white">{meal.totalProtein}g</div>
					<div class="text-white/50 text-sm">Protein</div>
				</div>
				<div class="text-center">
					<div class="text-2xl font-bold text-white">{meal.totalFat}g</div>
					<div class="text-white/50 text-sm">Fat</div>
				</div>
			</div>

			<!-- Food items -->
			<div class="space-y-3">
				<h3 class="text-white/50 text-sm font-medium">Food Items</h3>
				{#each meal.items as item, idx (idx)}
					<div class="flex items-center justify-between p-3 bg-white/5 rounded-lg">
						<span class="text-white">{item.name}</span>
						<span class="text-white/50 text-sm">
							{item.carbs}g C · {item.protein}g P · {item.fat}g F
						</span>
					</div>
				{/each}
			</div>

			<!-- AI confidence (if applicable) -->
			{#if meal.confidence !== undefined}
				<div class="flex items-center gap-2 text-sm text-white/50">
					<span>AI confidence:</span>
					<span class="font-medium">{Math.round(meal.confidence * 100)}%</span>
				</div>
			{/if}

			<!-- Action buttons -->
			<div class="flex gap-3 pt-2">
				<button
					onclick={onEdit}
					class="flex-1 py-4 px-4 rounded-xl bg-brand-accent/20 text-brand-accent text-base font-medium hover:bg-brand-accent/30 min-h-[44px]"
				>
					Edit Meal
				</button>
				<button
					onclick={onDelete}
					class="py-4 px-6 rounded-xl bg-red-600/20 text-red-400 text-base font-medium hover:bg-red-600/30 min-h-[44px]"
				>
					Delete
				</button>
			</div>
		</div>
	</div>
</div>
