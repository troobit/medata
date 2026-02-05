<script lang="ts">
	/**
	 * FoodItemCard component for displaying and editing a single food item.
	 * Req 3.7, 9.2: Large tap targets (44px minimum)
	 * Req 5.2: Inline editing of name, carbs, protein, fat
	 * Req 5.3: Remove item button
	 */
	import type { FoodItem } from '$lib/types/index.js';

	interface Props {
		item: FoodItem;
		confidence?: number;
		onUpdate: (item: FoodItem) => void;
		onRemove: () => void;
	}

	let { item, confidence, onUpdate, onRemove }: Props = $props();

	/**
	 * Handle name change.
	 */
	function handleNameChange(event: Event) {
		const target = event.target as HTMLInputElement;
		onUpdate({
			...item,
			name: target.value
		});
	}

	/**
	 * Handle macro value change.
	 */
	function handleMacroChange(field: 'carbs' | 'protein' | 'fat', event: Event) {
		const target = event.target as HTMLInputElement;
		const value = parseFloat(target.value) || 0;
		const clampedValue = Math.max(0, value);

		onUpdate({
			...item,
			[field]: clampedValue
		});
	}

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

	// Generate unique IDs for accessibility
	const inputId = $derived(`food-item-${item.name.replace(/\s+/g, '-').toLowerCase()}-${Math.random().toString(36).slice(2, 9)}`);
</script>

<div class="rounded-lg bg-white/5 p-3">
	<!-- Header row with name and remove button -->
	<div class="flex items-center gap-2 mb-3">
		<input
			type="text"
			value={item.name}
			onchange={handleNameChange}
			class="flex-1 bg-transparent border-b border-white/20 py-2 px-1 text-base font-medium text-white focus:border-brand-accent focus:outline-none min-h-[44px]"
			placeholder="Food name"
			aria-label="Food name"
		/>
		{#if confidence !== undefined}
			<span class="rounded px-2 py-1 text-xs {getConfidenceColour(confidence)}">
				{formatConfidence(confidence)}
			</span>
		{/if}
		<button
			onclick={onRemove}
			class="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-lg bg-red-600/20 text-red-400 hover:bg-red-600/30"
			aria-label="Remove item"
		>
			<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
				<path
					fill-rule="evenodd"
					d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
					clip-rule="evenodd"
				/>
			</svg>
		</button>
	</div>

	<!-- Macro inputs row -->
	<div class="flex gap-3">
		<!-- Carbs input - primary, highlighted -->
		<div class="flex-1">
			<label for="{inputId}-carbs" class="block text-xs text-white/50 mb-1">Carbs</label>
			<div class="relative">
				<input
					id="{inputId}-carbs"
					type="number"
					inputmode="decimal"
					value={item.carbs}
					onchange={(e) => handleMacroChange('carbs', e)}
					min="0"
					step="0.1"
					class="w-full bg-brand-accent/10 border border-brand-accent/30 rounded-lg py-3 px-3 text-lg font-bold text-brand-accent text-center focus:border-brand-accent focus:outline-none min-h-[44px]"
				/>
				<span class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-brand-accent/70">g</span>
			</div>
		</div>

		<!-- Protein input -->
		<div class="flex-1">
			<label for="{inputId}-protein" class="block text-xs text-white/50 mb-1">Protein</label>
			<div class="relative">
				<input
					id="{inputId}-protein"
					type="number"
					inputmode="decimal"
					value={item.protein}
					onchange={(e) => handleMacroChange('protein', e)}
					min="0"
					step="0.1"
					class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-3 text-lg font-bold text-white text-center focus:border-white/30 focus:outline-none min-h-[44px]"
				/>
				<span class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-white/50">g</span>
			</div>
		</div>

		<!-- Fat input -->
		<div class="flex-1">
			<label for="{inputId}-fat" class="block text-xs text-white/50 mb-1">Fat</label>
			<div class="relative">
				<input
					id="{inputId}-fat"
					type="number"
					inputmode="decimal"
					value={item.fat}
					onchange={(e) => handleMacroChange('fat', e)}
					min="0"
					step="0.1"
					class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-3 text-lg font-bold text-white text-center focus:border-white/30 focus:outline-none min-h-[44px]"
				/>
				<span class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-white/50">g</span>
			</div>
		</div>
	</div>
</div>
