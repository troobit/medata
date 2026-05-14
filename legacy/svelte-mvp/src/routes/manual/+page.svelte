<script lang="ts">
	/**
	 * Manual entry page for logging meals without photos.
	 * Req 3.5: Works without requiring a photo
	 * Req 4.2: Record source as manual
	 * Flow: ManualEntryForm → MealEditor → Save
	 */
	import { goto } from '$app/navigation';
	import { ManualEntryForm, MealEditor, ToastContainer } from '$lib/components/index.js';
	import { toastStore } from '$lib/stores/toast.svelte.js';
	import { createMeal } from '$lib/services/index.js';
	import type { FoodItem, CreateMealInput } from '$lib/types/index.js';

	// State machine for the flow
	type FlowState = 'entry' | 'review';
	let flowState = $state<FlowState>('entry');

	// Items collected from ManualEntryForm
	let collectedItems = $state<FoodItem[]>([]);

	// Saving state
	let saving = $state(false);

	/**
	 * Handle proceed from ManualEntryForm to MealEditor.
	 */
	function handleProceed(items: FoodItem[]) {
		collectedItems = items;
		flowState = 'review';
	}

	/**
	 * Handle cancel from ManualEntryForm - go back to home.
	 */
	function handleCancel() {
		goto('/');
	}

	/**
	 * Handle back from MealEditor to ManualEntryForm.
	 */
	function handleBack() {
		flowState = 'entry';
	}

	/**
	 * Handle save meal from MealEditor.
	 * Req 4.2: Record source as manual
	 * Req 4.6: Visual confirmation when meal saved
	 */
	async function handleSave(input: CreateMealInput) {
		saving = true;

		try {
			await createMeal(input);
			toastStore.success('Meal saved');
			goto('/');
		} catch (e) {
			toastStore.error(e instanceof Error ? e.message : 'Save failed. Try again.');
		} finally {
			saving = false;
		}
	}
</script>

<div class="flex flex-col gap-4">
	{#if flowState === 'entry'}
		<ManualEntryForm onProceed={handleProceed} onCancel={handleCancel} />
	{:else if flowState === 'review'}
		<MealEditor
			initialItems={collectedItems}
			source="manual"
			onSave={handleSave}
			onCancel={handleBack}
		/>
	{/if}
</div>

<ToastContainer />
