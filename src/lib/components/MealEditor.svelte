<script lang="ts">
	/**
	 * MealEditor component for editing and saving meals.
	 * Req 3.6, 5.1: Editable AI results before saving
	 * Req 3.2, 5.4: Add new food items
	 * Req 3.3, 5.5: Auto-recalculate totals on change
	 * Req 5.6: Preserve original AI confidence scores
	 * Req 6.1: Save any meal as a named preset
	 */
	import type { FoodItem, MealDataSource, CreateMealInput, CreatePresetInput, PresetCategory } from '$lib/types/index.js';
	import { sumMacros } from '$lib/utils/index.js';
	import FoodItemCard from './FoodItemCard.svelte';

	interface EditableFoodItem extends FoodItem {
		id: string;
		confidence?: number;
	}

	interface Props {
		initialItems?: FoodItem[];
		initialConfidences?: number[];
		imageUrl?: string;
		source: MealDataSource;
		overallConfidence?: number;
		onSave: (meal: CreateMealInput) => void;
		onCancel?: () => void;
		onSaveAsPreset?: (preset: CreatePresetInput) => void;
	}

	let {
		initialItems = [],
		initialConfidences = [],
		imageUrl,
		source,
		overallConfidence,
		onSave,
		onCancel,
		onSaveAsPreset
	}: Props = $props();

	/**
	 * Generate a unique ID for items.
	 */
	function generateId(): string {
		return Math.random().toString(36).slice(2, 11);
	}

	// Convert initial items to editable items with IDs (runs once on mount)
	let items = $state<EditableFoodItem[]>(
		(() => {
			const initItems = initialItems;
			const initConfs = initialConfidences;
			return initItems.map((item, index): EditableFoodItem => {
				const conf = initConfs[index];
				return {
					...item,
					id: generateId(),
					...(conf !== undefined ? { confidence: conf } : {})
				};
			});
		})()
	);

	// Timestamp state - default to now (Req 4.4)
	let timestamp = $state(Date.now());

	// Derived totals that auto-recalculate (Req 3.3, 5.5)
	let totals = $derived(sumMacros(items));

	// Track if we have any items
	let hasItems = $derived(items.length > 0);

	// Preset modal state
	let showPresetModal = $state(false);
	let presetName = $state('');
	let presetCategory = $state<PresetCategory>('meal');

	/**
	 * Update a food item at the given index.
	 */
	function updateItem(id: string, updated: FoodItem) {
		items = items.map((item): EditableFoodItem => {
			if (item.id === id) {
				return {
					...updated,
					id: item.id,
					...(item.confidence !== undefined ? { confidence: item.confidence } : {})
				};
			}
			return item;
		});
	}

	/**
	 * Remove a food item by ID.
	 */
	function removeItem(id: string) {
		items = items.filter((item) => item.id !== id);
	}

	/**
	 * Add a new empty food item (Req 3.2, 5.4).
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
	 * Handle save action.
	 */
	function handleSave() {
		// Filter out items with empty names
		const validItems = items
			.filter((item) => item.name.trim() !== '')
			.map(({ id, confidence, ...foodItem }) => foodItem);

		if (validItems.length === 0) {
			return;
		}

		const meal: CreateMealInput = {
			timestamp,
			items: validItems,
			totalCarbs: totals.carbs,
			totalProtein: totals.protein,
			totalFat: totals.fat,
			source,
			...(imageUrl !== undefined ? { imageUrl } : {}),
			...(overallConfidence !== undefined ? { confidence: overallConfidence } : {})
		};

		onSave(meal);
	}

	/**
	 * Handle timestamp change.
	 */
	function handleTimestampChange(event: Event) {
		const target = event.target as HTMLInputElement;
		const date = new Date(target.value);
		if (!isNaN(date.getTime())) {
			timestamp = date.getTime();
		}
	}

	/**
	 * Format timestamp for datetime-local input.
	 */
	function formatDatetimeLocal(ts: number): string {
		const date = new Date(ts);
		const pad = (n: number) => n.toString().padStart(2, '0');
		return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
	}

	/**
	 * Open the save as preset modal.
	 */
	function openPresetModal() {
		presetName = '';
		presetCategory = 'meal';
		showPresetModal = true;
	}

	/**
	 * Handle save as preset action.
	 * Req 6.1: Save any meal as a named preset (including emoji-only names)
	 */
	function handleSaveAsPreset() {
		if (!presetName.trim() || !onSaveAsPreset) {
			return;
		}

		// Filter out items with empty names
		const validItems = items
			.filter((item) => item.name.trim() !== '')
			.map(({ id, confidence, ...foodItem }) => foodItem);

		if (validItems.length === 0) {
			return;
		}

		const preset: CreatePresetInput = {
			name: presetName.trim(),
			category: presetCategory,
			items: validItems
		};

		onSaveAsPreset(preset);
		showPresetModal = false;
	}
</script>

<div class="flex flex-col gap-4">
	<!-- Image preview if available -->
	{#if imageUrl}
		<div class="relative rounded-lg overflow-hidden aspect-video bg-white/5">
			<img
				src={imageUrl}
				alt="Captured meal"
				class="w-full h-full object-cover"
			/>
		</div>
	{/if}

	<!-- Timestamp input (Req 4.4, 4.5) -->
	<div>
		<label for="meal-timestamp" class="block text-sm text-white/70 mb-1">When</label>
		<input
			id="meal-timestamp"
			type="datetime-local"
			value={formatDatetimeLocal(timestamp)}
			onchange={handleTimestampChange}
			class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-4 text-white focus:border-brand-accent focus:outline-none min-h-[44px]"
		/>
	</div>

	<!-- Food items list -->
	<div class="flex flex-col gap-3">
		<div class="flex items-center justify-between">
			<h3 class="text-sm font-medium text-white/70">Food Items</h3>
			{#if items.length > 0}
				<span class="text-sm text-white/50">{items.length} {items.length === 1 ? 'item' : 'items'}</span>
			{/if}
		</div>

		{#each items as item (item.id)}
			{#if item.confidence !== undefined}
				<FoodItemCard
					{item}
					confidence={item.confidence}
					onUpdate={(updated) => updateItem(item.id, updated)}
					onRemove={() => removeItem(item.id)}
				/>
			{:else}
				<FoodItemCard
					{item}
					onUpdate={(updated) => updateItem(item.id, updated)}
					onRemove={() => removeItem(item.id)}
				/>
			{/if}
		{/each}

		<!-- Add item button -->
		<button
			onclick={addItem}
			class="w-full rounded-lg border-2 border-dashed border-white/20 py-4 text-white/50 hover:border-white/30 hover:text-white/70 min-h-[44px] flex items-center justify-center gap-2"
		>
			<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
				<path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
			</svg>
			Add Food Item
		</button>
	</div>

	<!-- Totals display -->
	{#if hasItems}
		<div class="rounded-lg bg-white/10 p-4">
			<div class="text-sm font-medium text-white/70 mb-2">Total Macros</div>
			<div class="flex gap-6">
				<div>
					<span class="text-white/50">Carbs</span>
					<span class="ml-1 text-xl font-bold text-brand-accent">{Math.round(totals.carbs * 10) / 10}g</span>
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
			onclick={handleSave}
			disabled={!hasItems || items.every(i => i.name.trim() === '')}
			class="w-full rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
		>
			Save Meal
		</button>
		{#if onSaveAsPreset}
			<button
				onclick={openPresetModal}
				disabled={!hasItems || items.every(i => i.name.trim() === '')}
				class="w-full rounded-lg border border-brand-accent py-3 text-base font-medium text-brand-accent min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
			>
				Save as Preset
			</button>
		{/if}
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

<!-- Save as Preset Modal -->
{#if showPresetModal}
	<div class="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4">
		<div class="bg-gray-900 rounded-xl w-full max-w-sm p-6">
			<h2 class="text-xl font-semibold text-white mb-4">Save as Preset</h2>

			<!-- Name input -->
			<div class="mb-4">
				<label for="preset-name" class="block text-sm text-white/70 mb-1">Name</label>
				<input
					id="preset-name"
					type="text"
					bind:value={presetName}
					placeholder="e.g. Morning oatmeal or just emoji"
					class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-4 text-white placeholder:text-white/30 focus:border-brand-accent focus:outline-none min-h-[44px]"
				/>
			</div>

			<!-- Category selection -->
			<div class="mb-6">
				<span class="block text-sm text-white/70 mb-2">Category</span>
				<div class="flex gap-3" role="group" aria-label="Category">
					<button
						onclick={() => presetCategory = 'meal'}
						class="flex-1 rounded-lg py-3 text-base font-medium min-h-[44px] {presetCategory === 'meal' ? 'bg-brand-accent text-black' : 'bg-white/5 text-white/70 border border-white/10'}"
						aria-pressed={presetCategory === 'meal'}
					>
						Meal
					</button>
					<button
						onclick={() => presetCategory = 'snack'}
						class="flex-1 rounded-lg py-3 text-base font-medium min-h-[44px] {presetCategory === 'snack' ? 'bg-brand-accent text-black' : 'bg-white/5 text-white/70 border border-white/10'}"
						aria-pressed={presetCategory === 'snack'}
					>
						Snack
					</button>
				</div>
			</div>

			<!-- Modal actions -->
			<div class="flex gap-3">
				<button
					onclick={() => showPresetModal = false}
					class="flex-1 rounded-lg border border-white/20 py-3 text-base font-medium text-white/70 min-h-[44px]"
				>
					Cancel
				</button>
				<button
					onclick={handleSaveAsPreset}
					disabled={!presetName.trim()}
					class="flex-1 rounded-lg bg-brand-accent py-3 text-base font-semibold text-black min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
				>
					Save
				</button>
			</div>
		</div>
	</div>
{/if}
