<script lang="ts">
	/**
	 * Capture page - implements the full capture flow:
	 * CameraCapture → ImagePreview → AI Recognition → MealEditor → Save
	 * Req 9.3: Complete in 3 or fewer actions (Photo → Review → Save)
	 */
	import { goto } from '$app/navigation';
	import {
		CameraCapture,
		ImagePreview,
		FoodRecognitionResult,
		AIErrorFallback,
		MealEditor
	} from '$lib/components/index.js';
	import type { RecognisedFoodItem, FoodItem, CreateMealInput } from '$lib/types/index.js';
	import { toastStore } from '$lib/stores/index.js';

	// Flow states
	type FlowState =
		| 'capture'
		| 'preview'
		| 'recognising'
		| 'results'
		| 'error'
		| 'editing';

	let flowState = $state<FlowState>('capture');

	// Captured image data
	let capturedImage: Blob | null = $state(null);
	let imageUrl: string | null = $state(null);

	// AI recognition results
	let recognitionItems: RecognisedFoodItem[] = $state([]);
	let recognitionConfidence = $state(0);

	// Error state
	let errorType: 'timeout' | 'no_items' | 'ai_failure' | 'generic' = $state('generic');
	let errorMessage = $state('');
	let isRetrying = $state(false);

	/**
	 * Handle image capture from camera or gallery.
	 */
	function handleCapture(result: { foodImage: Blob; source: 'camera' | 'gallery' }) {
		capturedImage = result.foodImage;
		flowState = 'preview';
	}

	/**
	 * Handle capture cancellation.
	 */
	function handleCaptureCancel() {
		goto('/');
	}

	/**
	 * Handle preview confirmation - start AI recognition.
	 */
	async function handlePreviewConfirm() {
		if (!capturedImage) return;

		flowState = 'recognising';
		await performRecognition();
	}

	/**
	 * Handle retake from preview.
	 */
	function handleRetake() {
		capturedImage = null;
		flowState = 'capture';
	}

	/**
	 * Perform AI recognition via the provider-agnostic /api/recognition/analyse endpoint.
	 */
	async function performRecognition() {
		if (!capturedImage) return;

		try {
			// Convert Blob to base64
			const base64 = await blobToBase64(capturedImage);
			const mimeType = capturedImage.type || 'image/jpeg';

			const response = await fetch('/api/recognition/analyse', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ imageBase64: base64, mimeType })
			});

			if (!response.ok) {
				const errorBody = await response.json().catch(() => ({}));
				const message = errorBody.error || 'Recognition failed.';

				// Determine error type from status code
				if (response.status === 504) {
					errorType = 'timeout';
					errorMessage = message;
				} else if (response.status === 422) {
					errorType = 'no_items';
					errorMessage = message;
				} else if (response.status === 502 || response.status === 503) {
					errorType = 'ai_failure';
					errorMessage = message;
				} else {
					errorType = 'generic';
					errorMessage = message;
				}

				flowState = 'error';
				return;
			}

			const result = await response.json();

			recognitionItems = result.items;
			recognitionConfidence = result.overallConfidence;

			flowState = 'results';
		} catch {
			errorType = 'generic';
			errorMessage = 'Network error. Check connection and retry.';
			flowState = 'error';
		}
	}

	/**
	 * Convert Blob to base64 string (without data URL prefix).
	 */
	function blobToBase64(blob: Blob): Promise<string> {
		return new Promise((resolve, reject) => {
			const reader = new FileReader();
			reader.onloadend = () => {
				const dataUrl = reader.result as string;
				// Remove data URL prefix (e.g., "data:image/jpeg;base64,")
				const base64 = dataUrl.split(',')[1] ?? '';
				resolve(base64);
			};
			reader.onerror = reject;
			reader.readAsDataURL(blob);
		});
	}

	/**
	 * Handle confirmation of AI results - proceed to meal editor.
	 */
	function handleResultsConfirm(items: RecognisedFoodItem[]) {
		// Create object URL for image if we have one
		if (capturedImage) {
			imageUrl = URL.createObjectURL(capturedImage);
		}
		recognitionItems = items;
		flowState = 'editing';
	}

	/**
	 * Handle retry from error or results screen.
	 */
	async function handleRetry() {
		isRetrying = true;
		flowState = 'recognising';
		await performRecognition();
		isRetrying = false;
	}

	/**
	 * Handle manual entry from error or results screen.
	 */
	function handleManualEntry() {
		// Create object URL for image if we have one
		if (capturedImage) {
			imageUrl = URL.createObjectURL(capturedImage);
		}
		// Clear recognition items and go to editor with empty state
		recognitionItems = [];
		flowState = 'editing';
	}

	/**
	 * Handle meal save.
	 */
	async function handleSave(meal: CreateMealInput) {
		// For now, just show toast and go home
		// TODO: Wire to actual save API when meal storage is implemented
		toastStore.success('Meal saved');

		// Cleanup
		if (imageUrl) {
			URL.revokeObjectURL(imageUrl);
		}

		goto('/');
	}

	/**
	 * Handle cancel from meal editor.
	 */
	function handleEditorCancel() {
		if (imageUrl) {
			URL.revokeObjectURL(imageUrl);
		}
		goto('/');
	}

	// Convert RecognisedFoodItem to FoodItem (strip confidence)
	let foodItems = $derived<FoodItem[]>(
		recognitionItems.map(({ name, carbs, protein, fat }) => ({
			name,
			carbs,
			protein,
			fat
		}))
	);

	// Get confidences array for editor
	let confidences = $derived(recognitionItems.map((item) => item.confidence));

	// Meal source is always ai_image for the capture flow
	let mealSource = 'ai_image' as const;

	// Cleanup on unmount
	$effect(() => {
		return () => {
			if (imageUrl) {
				URL.revokeObjectURL(imageUrl);
			}
		};
	});
</script>

<div class="pb-4">
	{#if flowState === 'capture'}
		<CameraCapture onCapture={handleCapture} onCancel={handleCaptureCancel} />
	{:else if flowState === 'preview' && capturedImage}
		<ImagePreview
			image={capturedImage}
			onConfirm={handlePreviewConfirm}
			onRetake={handleRetake}
		/>
	{:else if flowState === 'recognising'}
		<div class="flex flex-col items-center justify-center gap-4 py-12">
			<div class="animate-pulse">
				<div class="h-16 w-16 rounded-full bg-brand-accent/20 flex items-center justify-center">
					<div class="h-8 w-8 rounded-full bg-brand-accent animate-ping"></div>
				</div>
			</div>
			<p class="text-white/70">Analysing your meal...</p>
		</div>
	{:else if flowState === 'results'}
		<FoodRecognitionResult
			items={recognitionItems}
			confidence={recognitionConfidence}
			onConfirm={handleResultsConfirm}
			onRetry={handleRetry}
			onManualEntry={handleManualEntry}
		/>
	{:else if flowState === 'error'}
		<AIErrorFallback
			{errorType}
			{errorMessage}
			onRetry={handleRetry}
			onManualEntry={handleManualEntry}
			{isRetrying}
		/>
	{:else if flowState === 'editing'}
		{#if imageUrl}
			<MealEditor
				initialItems={foodItems}
				initialConfidences={confidences}
				{imageUrl}
				source={mealSource}
				overallConfidence={recognitionConfidence}
				onSave={handleSave}
				onCancel={handleEditorCancel}
			/>
		{:else}
			<MealEditor
				initialItems={foodItems}
				initialConfidences={confidences}
				source={mealSource}
				overallConfidence={recognitionConfidence}
				onSave={handleSave}
				onCancel={handleEditorCancel}
			/>
		{/if}
	{/if}
</div>
