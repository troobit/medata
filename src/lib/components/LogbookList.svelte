<script lang="ts">
	/**
	 * LogbookList component for displaying meal history.
	 * Req 8.1: Chronological list, newest first
	 * Req 8.2: Show timestamp, total carbs, item count
	 * Per design section 3.2: Expandable cards
	 */
	import { SvelteSet } from 'svelte/reactivity';
	import type { Meal } from '$lib/types/index.js';

	interface Props {
		meals: Meal[];
		onSelect: (meal: Meal) => void;
		onEdit: (meal: Meal) => void;
		onDelete: (mealId: string) => void;
	}

	let { meals, onSelect, onEdit, onDelete }: Props = $props();

	// Track which meals are expanded
	let expandedMeals = new SvelteSet<string>();

	/**
	 * Toggle meal expansion.
	 */
	function toggleExpanded(mealId: string) {
		if (expandedMeals.has(mealId)) {
			expandedMeals.delete(mealId);
		} else {
			expandedMeals.add(mealId);
		}
	}

	/**
	 * Format timestamp for display.
	 */
	function formatTime(timestamp: number): string {
		const date = new Date(timestamp);
		return date.toLocaleTimeString('en-IE', {
			hour: '2-digit',
			minute: '2-digit',
			hour12: false
		});
	}

	/**
	 * Format date for display.
	 */
	function formatDate(timestamp: number): string {
		const date = new Date(timestamp);
		const today = new Date();
		const yesterday = new Date(today);
		yesterday.setDate(yesterday.getDate() - 1);

		// Check if same day
		if (date.toDateString() === today.toDateString()) {
			return 'Today';
		}
		if (date.toDateString() === yesterday.toDateString()) {
			return 'Yesterday';
		}

		return date.toLocaleDateString('en-IE', {
			weekday: 'short',
			day: 'numeric',
			month: 'short'
		});
	}

	/**
	 * Get data source label for display.
	 */
	function getSourceLabel(source: Meal['source']): string {
		switch (source) {
			case 'ai_image':
				return '📷';
			case 'manual':
				return '✏️';
			case 'preset':
				return '📋';
			default:
				return '';
		}
	}

	/**
	 * Group meals by date.
	 */
	const groupedMeals = $derived.by(() => {
		const groups = new Map<string, Meal[]>();

		for (const meal of meals) {
			const dateKey = new Date(meal.timestamp).toDateString();
			if (!groups.has(dateKey)) {
				groups.set(dateKey, []);
			}
			groups.get(dateKey)!.push(meal);
		}

		// Sort each group by timestamp descending
		for (const [, mealList] of groups) {
			mealList.sort((a, b) => b.timestamp - a.timestamp);
		}

		// Return as array sorted by date descending
		return Array.from(groups.entries())
			.sort(([a], [b]) => new Date(b).getTime() - new Date(a).getTime())
			.map(([dateStr, mealList]) => ({
				date: new Date(dateStr),
				meals: mealList
			}));
	});
</script>

<div class="space-y-6">
	{#if meals.length === 0}
		<div class="text-center py-12">
			<p class="text-white/50 text-lg">No meals yet</p>
			<p class="text-white/30 text-sm mt-2">Your meal history will appear here</p>
		</div>
	{:else}
		{#each groupedMeals as { date, meals: dayMeals } (date.toISOString())}
			<div class="space-y-3">
				<!-- Date header -->
				<h3 class="text-white/50 text-sm font-medium px-1">
					{formatDate(date.getTime())}
				</h3>

				<!-- Meals for this date -->
				{#each dayMeals as meal (meal.id)}
					{@const isExpanded = expandedMeals.has(meal.id)}
					<div class="bg-white/5 rounded-xl overflow-hidden">
						<!-- Meal summary row -->
						<button
							onclick={() => toggleExpanded(meal.id)}
							class="w-full flex items-center gap-3 p-4 min-h-[60px] text-left hover:bg-white/5 transition-colors"
							aria-expanded={isExpanded}
						>
							<!-- Time -->
							<span class="text-white/50 text-sm font-mono w-12">
								{formatTime(meal.timestamp)}
							</span>

							<!-- Source icon -->
							<span class="text-lg" title={meal.source}>
								{getSourceLabel(meal.source)}
							</span>

							<!-- Item count -->
							<span class="text-white/70 text-sm flex-1">
								{meal.items.length} item{meal.items.length !== 1 ? 's' : ''}
							</span>

							<!-- Total carbs - prominent -->
							<span class="text-brand-accent font-bold text-lg">
								{Math.round(meal.totalCarbs)}g
							</span>

							<!-- Expand icon -->
							<svg
								class="w-5 h-5 text-white/30 transition-transform {isExpanded
									? 'rotate-180'
									: ''}"
								xmlns="http://www.w3.org/2000/svg"
								viewBox="0 0 20 20"
								fill="currentColor"
							>
								<path
									fill-rule="evenodd"
									d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
									clip-rule="evenodd"
								/>
							</svg>
						</button>

						<!-- Expanded content -->
						{#if isExpanded}
							<div class="border-t border-white/10 p-4 space-y-4">
								<!-- Food items -->
								<div class="space-y-2">
									{#each meal.items as item, idx (idx)}
										<div class="flex items-center justify-between text-sm">
											<span class="text-white/80">{item.name}</span>
											<span class="text-white/50">
												{item.carbs}g C · {item.protein}g P · {item.fat}g F
											</span>
										</div>
									{/each}
								</div>

								<!-- Macro totals -->
								<div class="flex gap-4 pt-2 border-t border-white/10">
									<div class="flex-1 text-center">
										<div class="text-brand-accent font-bold">{meal.totalCarbs}g</div>
										<div class="text-white/40 text-xs">Carbs</div>
									</div>
									<div class="flex-1 text-center">
										<div class="text-white font-bold">{meal.totalProtein}g</div>
										<div class="text-white/40 text-xs">Protein</div>
									</div>
									<div class="flex-1 text-center">
										<div class="text-white font-bold">{meal.totalFat}g</div>
										<div class="text-white/40 text-xs">Fat</div>
									</div>
								</div>

								<!-- Action buttons -->
								<div class="flex gap-2 pt-2">
									<button
										onclick={() => onSelect(meal)}
										class="flex-1 py-3 px-4 rounded-lg bg-white/10 text-white text-sm font-medium hover:bg-white/20 min-h-[44px]"
									>
										View
									</button>
									<button
										onclick={() => onEdit(meal)}
										class="flex-1 py-3 px-4 rounded-lg bg-brand-accent/20 text-brand-accent text-sm font-medium hover:bg-brand-accent/30 min-h-[44px]"
									>
										Edit
									</button>
									<button
										onclick={() => onDelete(meal.id)}
										class="py-3 px-4 rounded-lg bg-red-600/20 text-red-400 text-sm font-medium hover:bg-red-600/30 min-h-[44px]"
									>
										Delete
									</button>
								</div>
							</div>
						{/if}
					</div>
				{/each}
			</div>
		{/each}
	{/if}
</div>
