<script lang="ts">
	/**
	 * Home page with action buttons and recent meals logbook.
	 * Per design section 7.5: Show recent meals on home page
	 */
	import { goto } from '$app/navigation';
	import { LogbookList, MealDetail, MealEditor, ToastContainer } from '$lib/components/index.js';
	import { toastStore } from '$lib/stores/toast.svelte.js';
	import { getMealsByDay, updateMeal, deleteMeal } from '$lib/services/index.js';
	import type { Meal, UpdateMealInput } from '$lib/types/index.js';
	import { sumMacros } from '$lib/utils/index.js';

	// Load recent meals (today and yesterday)
	let meals = $state<Meal[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	// Modal state
	let selectedMeal = $state<Meal | null>(null);
	let editingMeal = $state<Meal | null>(null);
	let deleteConfirmMeal = $state<Meal | null>(null);

	/**
	 * Load recent meals from API.
	 */
	async function loadMeals() {
		loading = true;
		error = null;

		try {
			const today = new Date();
			const yesterday = new Date(today);
			yesterday.setDate(yesterday.getDate() - 1);

			// Fetch meals for today and yesterday in parallel
			const [todayMeals, yesterdayMeals] = await Promise.all([
				getMealsByDay(today),
				getMealsByDay(yesterday)
			]);

			// Combine and sort by timestamp descending
			meals = [...todayMeals, ...yesterdayMeals].sort((a, b) => b.timestamp - a.timestamp);
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to load meals';
			console.error('Load meals error:', e);
		} finally {
			loading = false;
		}
	}

	// Load meals on mount
	$effect(() => {
		loadMeals();
	});

	/**
	 * Handle meal selection (view details).
	 */
	function handleSelectMeal(meal: Meal) {
		selectedMeal = meal;
	}

	/**
	 * Handle edit meal action.
	 */
	function handleEditMeal(meal: Meal) {
		selectedMeal = null;
		editingMeal = meal;
	}

	/**
	 * Handle delete meal action.
	 */
	function handleDeleteMeal(mealId: string) {
		const meal = meals.find((m) => m.id === mealId);
		if (meal) {
			selectedMeal = null;
			deleteConfirmMeal = meal;
		}
	}

	/**
	 * Confirm deletion.
	 */
	async function confirmDelete() {
		if (!deleteConfirmMeal) return;

		try {
			await deleteMeal(deleteConfirmMeal.id);
			meals = meals.filter((m) => m.id !== deleteConfirmMeal!.id);
			toastStore.success('Meal deleted');
			deleteConfirmMeal = null;
		} catch (e) {
			toastStore.error(e instanceof Error ? e.message : 'Delete failed');
		}
	}

	/**
	 * Handle save edited meal.
	 */
	async function handleSaveEdit(input: {
		timestamp: number;
		items: import('$lib/types/index.js').FoodItem[];
		totalCarbs: number;
		totalProtein: number;
		totalFat: number;
		source: import('$lib/types/index.js').MealDataSource;
		imageUrl?: string;
		confidence?: number;
	}) {
		if (!editingMeal) return;

		const updates: UpdateMealInput = {
			timestamp: input.timestamp,
			items: input.items,
			totalCarbs: input.totalCarbs,
			totalProtein: input.totalProtein,
			totalFat: input.totalFat
		};

		// Only add imageUrl if defined
		if (input.imageUrl !== undefined) {
			updates.imageUrl = input.imageUrl;
		}

		try {
			const updated = await updateMeal(editingMeal.id, updates);
			meals = meals.map((m) => (m.id === updated.id ? updated : m));
			toastStore.success('Meal updated');
			editingMeal = null;
		} catch (e) {
			toastStore.error(e instanceof Error ? e.message : 'Update failed');
		}
	}

	/**
	 * Close all modals.
	 */
	function closeModals() {
		selectedMeal = null;
		editingMeal = null;
		deleteConfirmMeal = null;
	}
</script>

<div class="flex flex-col gap-4">
	<!-- Action buttons -->
	<a
		href="/capture"
		class="flex items-center justify-center gap-2 min-h-[44px] px-6 py-4 bg-brand-accent text-primary-background font-semibold rounded-lg hover:opacity-90 transition-opacity"
	>
		Capture Meal
	</a>

	<a
		href="/manual"
		class="flex items-center justify-center gap-2 min-h-[44px] px-6 py-4 bg-white/10 text-white font-semibold rounded-lg hover:bg-white/20 transition-colors"
	>
		Manual Entry
	</a>

	<a
		href="/presets"
		class="flex items-center justify-center gap-2 min-h-[44px] px-6 py-4 bg-white/10 text-white font-semibold rounded-lg hover:bg-white/20 transition-colors"
	>
		From Preset
	</a>

	<hr class="border-white/10 my-4" />

	<!-- Logbook section -->
	<section>
		<h2 class="text-lg font-medium text-white/70 mb-3">Recent Meals</h2>

		{#if loading}
			<div class="flex items-center justify-center py-8">
				<div class="animate-spin h-6 w-6 border-2 border-brand-accent border-t-transparent rounded-full"></div>
			</div>
		{:else if error}
			<div class="text-center py-8">
				<p class="text-red-400 mb-2">{error}</p>
				<button
					onclick={loadMeals}
					class="text-brand-accent hover:underline"
				>
					Try again
				</button>
			</div>
		{:else}
			<LogbookList
				{meals}
				onSelect={handleSelectMeal}
				onEdit={handleEditMeal}
				onDelete={handleDeleteMeal}
			/>
		{/if}
	</section>
</div>

<!-- Meal detail modal -->
{#if selectedMeal}
	<MealDetail
		meal={selectedMeal}
		onEdit={() => handleEditMeal(selectedMeal!)}
		onDelete={() => handleDeleteMeal(selectedMeal!.id)}
		onClose={closeModals}
	/>
{/if}

<!-- Edit meal modal -->
{#if editingMeal}
	<div class="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
		<!-- Backdrop -->
		<button class="absolute inset-0 bg-black/80" onclick={closeModals} aria-label="Close"></button>

		<!-- Modal content -->
		<div class="relative w-full max-w-lg bg-gray-900 rounded-t-2xl sm:rounded-2xl max-h-[90vh] overflow-y-auto p-4">
			<h2 class="text-lg font-semibold text-white mb-4">Edit Meal</h2>
			{#if editingMeal.imageUrl !== undefined && editingMeal.confidence !== undefined}
				{@const editorImageUrl = editingMeal.imageUrl}
				{@const editorConfidence = editingMeal.confidence}
				<MealEditor
					initialItems={editingMeal.items}
					imageUrl={editorImageUrl}
					source={editingMeal.source}
					overallConfidence={editorConfidence}
					onSave={handleSaveEdit}
					onCancel={closeModals}
				/>
			{:else if editingMeal.imageUrl !== undefined}
				{@const editorImageUrl = editingMeal.imageUrl}
				<MealEditor
					initialItems={editingMeal.items}
					imageUrl={editorImageUrl}
					source={editingMeal.source}
					onSave={handleSaveEdit}
					onCancel={closeModals}
				/>
			{:else if editingMeal.confidence !== undefined}
				{@const editorConfidence = editingMeal.confidence}
				<MealEditor
					initialItems={editingMeal.items}
					source={editingMeal.source}
					overallConfidence={editorConfidence}
					onSave={handleSaveEdit}
					onCancel={closeModals}
				/>
			{:else}
				<MealEditor
					initialItems={editingMeal.items}
					source={editingMeal.source}
					onSave={handleSaveEdit}
					onCancel={closeModals}
				/>
			{/if}
		</div>
	</div>
{/if}

<!-- Delete confirmation modal -->
{#if deleteConfirmMeal}
	<div class="fixed inset-0 z-50 flex items-center justify-center">
		<!-- Backdrop -->
		<button class="absolute inset-0 bg-black/80" onclick={closeModals} aria-label="Close"></button>

		<!-- Modal content -->
		<div class="relative w-full max-w-sm bg-gray-900 rounded-2xl p-6">
			<h2 class="text-lg font-semibold text-white mb-2">Delete Meal?</h2>
			<p class="text-white/70 mb-6">
				This will permanently delete this meal with {deleteConfirmMeal.items.length} item{deleteConfirmMeal.items.length !== 1 ? 's' : ''}.
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
