<script lang="ts">
	/**
	 * PresetList component for displaying all presets.
	 * Req 6.3: List all presets
	 * Groups presets by category (meal/snack)
	 * Task 51: Tap preset to apply
	 */
	import type { Preset, PresetCategory } from '$lib/types/index.js';
	import PresetCard from './PresetCard.svelte';

	interface Props {
		presets: Preset[];
		onApply: (preset: Preset) => void;
		onEdit: (preset: Preset) => void;
		onDelete: (preset: Preset) => void;
	}

	let { presets, onApply, onEdit, onDelete }: Props = $props();

	/**
	 * Group presets by category.
	 */
	const groupedPresets = $derived.by(() => {
		const groups = new Map<PresetCategory, Preset[]>();
		groups.set('meal', []);
		groups.set('snack', []);

		for (const preset of presets) {
			const group = groups.get(preset.category);
			if (group) {
				group.push(preset);
			}
		}

		// Sort each group by name
		for (const [, presetList] of groups) {
			presetList.sort((a, b) => a.name.localeCompare(b.name));
		}

		return groups;
	});

	/**
	 * Get category display label.
	 */
	function getCategoryLabel(category: PresetCategory): string {
		switch (category) {
			case 'meal':
				return 'Meals';
			case 'snack':
				return 'Snacks';
		}
	}
</script>

<div class="space-y-6">
	{#if presets.length === 0}
		<div class="text-center py-12">
			<p class="text-white/50 text-lg">No presets yet</p>
			<p class="text-white/30 text-sm mt-2">Save a meal as preset to see it here</p>
		</div>
	{:else}
		<!-- Meals category -->
		{@const meals = groupedPresets.get('meal') ?? []}
		{#if meals.length > 0}
			<div class="space-y-3">
				<h3 class="text-white/50 text-sm font-medium px-1">
					{getCategoryLabel('meal')}
				</h3>
				<div class="space-y-2">
					{#each meals as preset (preset.id)}
						<PresetCard
							{preset}
							{onApply}
							{onEdit}
							{onDelete}
						/>
					{/each}
				</div>
			</div>
		{/if}

		<!-- Snacks category -->
		{@const snacks = groupedPresets.get('snack') ?? []}
		{#if snacks.length > 0}
			<div class="space-y-3">
				<h3 class="text-white/50 text-sm font-medium px-1">
					{getCategoryLabel('snack')}
				</h3>
				<div class="space-y-2">
					{#each snacks as preset (preset.id)}
						<PresetCard
							{preset}
							{onApply}
							{onEdit}
							{onDelete}
						/>
					{/each}
				</div>
			</div>
		{/if}
	{/if}
</div>
