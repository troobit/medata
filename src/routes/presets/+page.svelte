<script lang="ts">
	/**
	 * Presets page for viewing, applying, editing, and deleting presets.
	 * Req 6.3: List all presets
	 * Task 52: Apply preset to create new meal
	 * Task 53: Edit/delete preset functionality
	 */
	import { goto } from '$app/navigation';
	import { PresetList, MealEditor, ToastContainer } from '$lib/components/index.js';
	import { toastStore } from '$lib/stores/toast.svelte.js';
	import {
		getPresets,
		deletePreset,
		updatePreset,
		createMeal,
		createPreset
	} from '$lib/services/index.js';
	import type {
		Preset,
		CreateMealInput,
		UpdatePresetInput,
		CreatePresetInput,
		PresetCategory
	} from '$lib/types/index.js';
	import { sumMacros } from '$lib/utils/index.js';

	// Load presets
	let presets = $state<Preset[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	// Modal state
	let applyingPreset = $state<Preset | null>(null);
	let editingPreset = $state<Preset | null>(null);
	let deleteConfirmPreset = $state<Preset | null>(null);

	// Edit modal form state
	let editName = $state('');
	let editCategory = $state<PresetCategory>('meal');

	/**
	 * Load presets from API.
	 */
	async function loadPresets() {
		loading = true;
		error = null;

		try {
			presets = await getPresets();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load presets';
			console.error('Load presets error:', e);
		} finally {
			loading = false;
		}
	}

	// Load presets on mount
	$effect(() => {
		loadPresets();
	});

	/**
	 * Handle apply preset (open meal editor with preset data).
	 * Req 6.3: Apply preset to create new meal in a single action
	 * Req 6.8: Allow modification before saving
	 */
	function handleApply(preset: Preset) {
		applyingPreset = preset;
	}

	/**
	 * Handle edit preset action.
	 * Req 6.6: Edit preset details after creation
	 */
	function handleEdit(preset: Preset) {
		editingPreset = preset;
		editName = preset.name;
		editCategory = preset.category;
	}

	/**
	 * Handle delete preset action.
	 * Req 6.7: Delete presets
	 */
	function handleDelete(preset: Preset) {
		deleteConfirmPreset = preset;
	}

	/**
	 * Confirm deletion.
	 */
	async function confirmDelete() {
		if (!deleteConfirmPreset) return;

		try {
			await deletePreset(deleteConfirmPreset.id);
			presets = presets.filter((p) => p.id !== deleteConfirmPreset!.id);
			toastStore.success('Preset deleted');
			deleteConfirmPreset = null;
		} catch (e) {
			toastStore.error(e instanceof Error ? e.message : 'Delete failed');
		}
	}

	/**
	 * Save edited preset.
	 */
	async function saveEditedPreset() {
		if (!editingPreset || !editName.trim()) return;

		const updates: UpdatePresetInput = {
			name: editName.trim(),
			category: editCategory
		};

		try {
			const updated = await updatePreset(editingPreset.id, updates);
			presets = presets.map((p) => (p.id === updated.id ? updated : p));
			toastStore.success('Preset updated');
			editingPreset = null;
		} catch (e) {
			toastStore.error(e instanceof Error ? e.message : 'Update failed');
		}
	}

	/**
	 * Handle save meal from preset.
	 * Creates a new meal with source: 'preset'.
	 */
	async function handleSaveMealFromPreset(input: CreateMealInput) {
		try {
			await createMeal({
				...input,
				source: 'preset'
			});
			toastStore.success('Meal saved');
			applyingPreset = null;
			goto('/');
		} catch (e) {
			toastStore.error(e instanceof Error ? e.message : 'Save failed');
		}
	}

	/**
	 * Handle save as new preset from meal editor.
	 */
	async function handleSaveAsPreset(input: CreatePresetInput) {
		try {
			const newPreset = await createPreset(input);
			presets = [...presets, newPreset];
			toastStore.success('Preset saved');
		} catch (e) {
			toastStore.error(e instanceof Error ? e.message : 'Save failed');
		}
	}

	/**
	 * Close all modals.
	 */
	function closeModals() {
		applyingPreset = null;
		editingPreset = null;
		deleteConfirmPreset = null;
	}
</script>

<div class="flex flex-col gap-4">
	<!-- Header with back button -->
	<div class="flex items-center gap-3 mb-2">
		<a
			href="/"
			class="min-w-[44px] min-h-[44px] flex items-center justify-center rounded-lg bg-white/5 text-white/70 hover:bg-white/10"
			aria-label="Back to home"
		>
			<svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
				<path
					fill-rule="evenodd"
					d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z"
					clip-rule="evenodd"
				/>
			</svg>
		</a>
		<h1 class="text-xl font-semibold text-white">Presets</h1>
	</div>

	<!-- Presets list -->
	{#if loading}
		<div class="flex items-center justify-center py-12">
			<div class="animate-spin h-6 w-6 border-2 border-brand-accent border-t-transparent rounded-full"></div>
		</div>
	{:else if error}
		<div class="text-center py-12">
			<p class="text-red-400 mb-2">{error}</p>
			<button onclick={loadPresets} class="text-brand-accent hover:underline">
				Try again
			</button>
		</div>
	{:else}
		<PresetList
			{presets}
			onApply={handleApply}
			onEdit={handleEdit}
			onDelete={handleDelete}
		/>
	{/if}
</div>

<!-- Apply preset modal (Meal Editor) -->
{#if applyingPreset}
	<div class="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
		<!-- Backdrop -->
		<button class="absolute inset-0 bg-black/80" onclick={closeModals} aria-label="Close"></button>

		<!-- Modal content -->
		<div class="relative w-full max-w-lg bg-gray-900 rounded-t-2xl sm:rounded-2xl max-h-[90vh] overflow-y-auto p-4">
			<h2 class="text-lg font-semibold text-white mb-4">
				Apply Preset: {applyingPreset.name}
			</h2>
			<MealEditor
				initialItems={applyingPreset.items}
				source="preset"
				onSave={handleSaveMealFromPreset}
				onCancel={closeModals}
				onSaveAsPreset={handleSaveAsPreset}
			/>
		</div>
	</div>
{/if}

<!-- Edit preset modal -->
{#if editingPreset}
	<div class="fixed inset-0 z-50 flex items-center justify-center">
		<!-- Backdrop -->
		<button class="absolute inset-0 bg-black/80" onclick={closeModals} aria-label="Close"></button>

		<!-- Modal content -->
		<div class="relative w-full max-w-sm bg-gray-900 rounded-2xl p-6">
			<h2 class="text-xl font-semibold text-white mb-4">Edit Preset</h2>

			<!-- Name input -->
			<div class="mb-4">
				<label for="edit-preset-name" class="block text-sm text-white/70 mb-1">Name</label>
				<input
					id="edit-preset-name"
					type="text"
					bind:value={editName}
					class="w-full bg-white/5 border border-white/10 rounded-lg py-3 px-4 text-white placeholder:text-white/30 focus:border-brand-accent focus:outline-none min-h-[44px]"
				/>
			</div>

			<!-- Category selection -->
			<div class="mb-6">
				<span class="block text-sm text-white/70 mb-2">Category</span>
				<div class="flex gap-3" role="group" aria-label="Category">
					<button
						onclick={() => (editCategory = 'meal')}
						class="flex-1 rounded-lg py-3 text-base font-medium min-h-[44px] {editCategory === 'meal'
							? 'bg-brand-accent text-black'
							: 'bg-white/5 text-white/70 border border-white/10'}"
						aria-pressed={editCategory === 'meal'}
					>
						Meal
					</button>
					<button
						onclick={() => (editCategory = 'snack')}
						class="flex-1 rounded-lg py-3 text-base font-medium min-h-[44px] {editCategory === 'snack'
							? 'bg-brand-accent text-black'
							: 'bg-white/5 text-white/70 border border-white/10'}"
						aria-pressed={editCategory === 'snack'}
					>
						Snack
					</button>
				</div>
			</div>

			<!-- Modal actions -->
			<div class="flex gap-3">
				<button
					onclick={closeModals}
					class="flex-1 rounded-lg border border-white/20 py-3 text-base font-medium text-white/70 min-h-[44px]"
				>
					Cancel
				</button>
				<button
					onclick={saveEditedPreset}
					disabled={!editName.trim()}
					class="flex-1 rounded-lg bg-brand-accent py-3 text-base font-semibold text-black min-h-[44px] disabled:opacity-50 disabled:cursor-not-allowed"
				>
					Save
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Delete confirmation modal -->
{#if deleteConfirmPreset}
	<div class="fixed inset-0 z-50 flex items-center justify-center">
		<!-- Backdrop -->
		<button class="absolute inset-0 bg-black/80" onclick={closeModals} aria-label="Close"></button>

		<!-- Modal content -->
		<div class="relative w-full max-w-sm bg-gray-900 rounded-2xl p-6">
			<h2 class="text-lg font-semibold text-white mb-2">Delete Preset?</h2>
			<p class="text-white/70 mb-6">
				This will permanently delete "{deleteConfirmPreset.name}".
			</p>
			<div class="flex gap-3">
				<button
					onclick={closeModals}
					class="flex-1 py-3 px-4 rounded-lg bg-white/10 text-white font-medium hover:bg-white/20 min-h-[44px]"
				>
					Cancel
				</button>
				<button
					onclick={confirmDelete}
					class="flex-1 py-3 px-4 rounded-lg bg-red-600 text-white font-medium hover:bg-red-700 min-h-[44px]"
				>
					Delete
				</button>
			</div>
		</div>
	</div>
{/if}

<ToastContainer />
