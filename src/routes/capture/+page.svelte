<script lang="ts">
	/**
	 * Capture page - implements the full capture flow:
	 * CameraCapture → ImagePreview → AI Recognition → MealEditor → Save
	 * Req 9.3: Complete in 3 or fewer actions (Photo → Review → Save)
	 */
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import {
		CameraCapture,
		ImagePreview,
		FoodRecognitionResult,
		AIErrorFallback,
		MealEditor,
		MockModeBanner,
		ManualEntryCTA
	} from '$lib/components/index.js';
	import type { RecognisedFoodItem, FoodItem, CreateMealInput } from '$lib/types/index.js';
	import { toastStore } from '$lib/stores/index.js';
	import { createMeal, uploadImage } from '$lib/services/meal-api.js';

	// Recognition status from /api/recognition/status
	let statusLoading = $state(true);
	let recognitionConfigured = $state(false);
	let mockMode = $state(false);

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

	// Save state
	let isSaving = $state(false);

	// Max image size: 10MB
	const MAX_IMAGE_SIZE = 10 * 1024 * 1024;

	/**
	 * Fetch recognition status on mount.
	 * Defaults to { configured: false, mockMode: false } on error.
	 */
	onMount(async () => {
		try {
			const response = await fetch('/api/recognition/status');
			if (response.ok) {
				const data = await response.json();
				recognitionConfigured = data.configured ?? false;
				mockMode = data.mockMode ?? false;
			}
		} catch {
			// Safe default: treat as unconfigured
		} finally {
			statusLoading = false;
		}
	});

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

		// Client-side 10MB image size check
		if (capturedImage.size > MAX_IMAGE_SIZE) {
			toastStore.error('Image is too large. Please use a photo under 10MB.');
			return;
		}

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
	 * Handle meal save — POST /api/meals + image upload to Blob Storage.
	 * Req 6.4: Image uploaded to Blob Storage, meal persisted to Cosmos DB.
	 * Req 11.3: If image upload fails, meal saves without image.
	 */
	async function handleSave(meal: CreateMealInput) {
		if (isSaving) return;
		isSaving = true;

		try {
			// Attempt image upload if we have a captured image (Req 6.4)
			// If upload fails, save meal without image (Req 11.3)
			let uploadedImageUrl: string | undefined;
			if (capturedImage) {
				try {
					const mimeType = capturedImage.type || 'image/jpeg';
					const extension = mimeType === 'image/png' ? 'png' : 'jpg';
					const file = new File([capturedImage], `capture.${extension}`, { type: mimeType });
					uploadedImageUrl = await uploadImage(file);
				} catch {
					// Req 11.3: Image upload failure is non-fatal — meal saves without image
				}
			}

			// Build final meal input with uploaded image URL
			const mealInput: CreateMealInput = {
				...meal,
				...(uploadedImageUrl ? { imageUrl: uploadedImageUrl } : {})
			};

			await createMeal(mealInput);
			toastStore.success('Meal saved');

			// Cleanup
			if (imageUrl) {
				URL.revokeObjectURL(imageUrl);
			}

			goto('/');
		} catch {
			toastStore.error('Service unavailable — meal not saved.');
			// Req 11.1: Editor state retained on failed save — don't navigate away
		} finally {
			isSaving = false;
		}
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
	{#if statusLoading}
		<!-- Skeleton loading state during status fetch (prevents layout shift) -->
		<div class="flex flex-col gap-4 py-8">
			<div class="animate-pulse space-y-4">
				<div class="h-48 rounded-lg bg-white/5"></div>
				<div class="h-12 rounded-lg bg-white/5"></div>
			</div>
		</div>
	{:else if !recognitionConfigured && !mockMode}
		<!-- Recognition not configured — show ManualEntryCTA -->
		<ManualEntryCTA />
	{:else}
		<!-- Recognition available — show capture flow -->
		{#if mockMode}
			<div class="mb-4">
				<MockModeBanner />
			</div>
		{/if}

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
					{mockMode}
				/>
			{:else}
				<MealEditor
					initialItems={foodItems}
					initialConfidences={confidences}
					source={mealSource}
					overallConfidence={recognitionConfidence}
					onSave={handleSave}
					onCancel={handleEditorCancel}
					{mockMode}
				/>
			{/if}
		{/if}
	{/if}
</div>
