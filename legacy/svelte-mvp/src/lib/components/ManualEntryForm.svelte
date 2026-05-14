<script lang="ts">
	/**
	 * ManualEntryForm component for quick manual food entry.
	 * Req 3.1: Minimal form with name, carbs, protein, fat
	 * Req 3.5: Works without requiring a photo
	 * Req 3.7: Large tap targets for quick adjustment
	 * Req 3.2: Add multiple food items to single meal
	 * Req 3.3: Auto-calculate aggregate totals
	 */
	import type { FoodItem } from '$lib/types/index.js';
	import { sumMacros } from '$lib/utils/index.js';

	interface Props {
		onProceed: (items: FoodItem[]) => void;
		onCancel?: () => void;
	}

	let { onProceed, onCancel }: Props = $props();

	interface EditableItem extends FoodItem {
		id: string;
	}

	/**
	 * Generate a unique ID for items.
	 */
	function generateId(): string {
		return Math.random().toString(36).slice(2, 11);
	}

	// Items being entered
	let items = $state<EditableItem[]>([
		{
			id: generateId(),
			name: '',
			carbs: 0,
			protein: 0,
			fat: 0
		}
	]);

	// Derived totals (Req 3.3)
	let totals = $derived(sumMacros(items));

	// Check if we have valid items to proceed
	let hasValidItems = $derived(items.some((item) => item.name.trim() !== ''));

	/**
	 * Update a food item field.
	 */
	function updateItem(id: string, field: keyof FoodItem, value: string | number) {
		items = items.map((item) => {
			if (item.id === id) {
				if (field === 'name') {
					return { ...item, [field]: value as string };
				} else {
					const numValue = typeof value === 'string' ? parseFloat(value) || 0 : value;
					return { ...item, [field]: Math.max(0, numValue) };
				}
			}
			return item;
		});
	}

	/**
	 * Add a new empty food item (Req 3.2).
	 */
	function addItem() {
		items = [
			...items,
			{
				id: generateId(),
				name: '',
				carbs: 0,
				protein: 0,
				fat: 0
			}
		];
	}

	/**
	 * Remove a food item by ID.
	 */
	function removeItem(id: string) {
		if (items.length > 1) {
			items = items.filter((item) => item.id !== id);
		}
	}

	/**
	 * Handle proceed to review/save.
	 */
	function handleProceed() {
		// Filter out items with empty names and remove internal ID
		const validItems: FoodItem[] = items
			.filter((item) => item.name.trim() !== '')
			.map(({ id, ...foodItem }) => foodItem);

		if (validItems.length > 0) {
			onProceed(validItems);
		}
	}
</script>

<div class="flex flex-col gap-4">
	<h2 class="text-lg font-semibold text-white">Add Food Items</h2>

	<!-- Food items list -->
	<div class="flex flex-col gap-3">
		{#each items as item, index (item.id)}
			<div class="rounded-lg bg-white/5 p-3">
				<!-- Item header with number and remove button -->
				<div class="flex items-center justify-between mb-3">
					<span class="text-sm text-white/50">Item {index + 1}</span>
					{#if items.length > 1}
						<button
							onclick={() => removeItem(item.id)}
							class="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-lg bg-red-600/20 text-red-400 hover:bg-red-600/30"
							aria-label="Remove item"
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
					{/if}
				</div>

				<!-- Name input -->
				<div class="mb-3">
					<label for="item-{item.id}-name" class="block text-xs text-white/50 mb-1">Name</label>
					<input
						id="item-{item.id}-name"
						type="text"
						value={item.name}
						onchange={(e) => updateItem(item.id, 'name', (e.target as HTMLInputElement).value)}
						class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-4 text-base text-white focus:border-brand-accent focus:outline-none min-h-[44px]"
						placeholder="Food name"
					/>
				</div>

				<!-- Macro inputs row -->
				<div class="flex gap-3">
					<!-- Carbs input - primary, highlighted (Req 3.7) -->
					<div class="flex-1">
						<label for="item-{item.id}-carbs" class="block text-xs text-white/50 mb-1">Carbs</label>
						<div class="relative">
							<input
								id="item-{item.id}-carbs"
								type="number"
								inputmode="decimal"
								value={item.carbs}
								onchange={(e) =>
									updateItem(item.id, 'carbs', (e.target as HTMLInputElement).value)}
								min="0"
								step="0.1"
								class="w-full bg-brand-accent/10 border border-brand-accent/30 rounded-lg py-3 px-3 text-lg font-bold text-brand-accent text-center focus:border-brand-accent focus:outline-none min-h-[44px]"
							/>
							<span class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-brand-accent/70"
								>g</span
							>
						</div>
					</div>

					<!-- Protein input -->
					<div class="flex-1">
						<label for="item-{item.id}-protein" class="block text-xs text-white/50 mb-1"
							>Protein</label
						>
						<div class="relative">
							<input
								id="item-{item.id}-protein"
								type="number"
								inputmode="decimal"
								value={item.protein}
								onchange={(e) =>
									updateItem(item.id, 'protein', (e.target as HTMLInputElement).value)}
								min="0"
								step="0.1"
								class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-3 text-lg font-bold text-white text-center focus:border-white/30 focus:outline-none min-h-[44px]"
							/>
							<span class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-white/50">g</span>
						</div>
					</div>

					<!-- Fat input (Req 3.7) -->
					<div class="flex-1">
						<label for="item-{item.id}-fat" class="block text-xs text-white/50 mb-1">Fat</label>
						<div class="relative">
							<input
								id="item-{item.id}-fat"
								type="number"
								inputmode="decimal"
								value={item.fat}
								onchange={(e) => updateItem(item.id, 'fat', (e.target as HTMLInputElement).value)}
								min="0"
								step="0.1"
								class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-3 text-lg font-bold text-white text-center focus:border-white/30 focus:outline-none min-h-[44px]"
							/>
							<span class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-white/50">g</span>
						</div>
					</div>
				</div>
			</div>
		{/each}

		<!-- Add item button (Req 3.2) -->
		<button
			onclick={addItem}
			class="w-full rounded-lg border-2 border-dashed border-white/20 py-4 text-white/50 hover:border-white/30 hover:text-white/70 min-h-[44px] flex items-center justify-center gap-2"
		>
			<svg
				xmlns="http://www.w3.org/2000/svg"
				class="h-5 w-5"
				viewBox="0 0 20 20"
				fill="currentColor"
			>
				<path
					fill-rule="evenodd"
					d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
					clip-rule="evenodd"
				/>
			</svg>
			Add Another Item
		</button>
	</div>

	<!-- Totals display (Req 3.3) -->
	{#if hasValidItems}
		<div class="rounded-lg bg-white/10 p-4">
			<div class="text-sm font-medium text-white/70 mb-2">Total Macros</div>
			<div class="flex gap-6">
				<div>
					<span class="text-white/50">Carbs</span>
					<span class="ml-1 text-xl font-bold text-brand-accent"
						>{Math.round(totals.carbs * 10) / 10}g</span
					>
				</div>
				<div>
					<span class="text-white/50">Protein</span>
					<span class="ml-1 text-xl font-bold">{Math.round(totals.protein * 10) / 10}g</span>
				</div>
				<div>
					<span class="text-white/50">Fat</span>
					<span class="ml-1 text-xl font-bold">{Math.round(totals.fat * 10) / 10}g</span>
				</div>
			</div>
		</div>
	{/if}

	<!-- Action buttons -->
	<div class="flex flex-col gap-2 mt-2">
		<button
			onclick={handleProceed}
			disabled={!hasValidItems}
			class="w-full rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
		>
			Review &amp; Save
		</button>
		{#if onCancel}
			<button
				onclick={onCancel}
				class="w-full rounded-lg border border-white/20 py-3 text-base font-medium text-white/70 min-h-[44px]"
			>
				Cancel
			</button>
		{/if}
	</div>
</div>
