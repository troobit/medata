<script lang="ts">
	/**
	 * CameraCapture component for capturing food photos.
	 * Req 1.1: Use rear-facing camera via MediaDevices API
	 * Req 1.2: Accept JPEG and PNG only
	 * Req 1.5: Mobile-first
	 * Req 1.6: Gallery upload fallback via file input
	 * Req 7.1: Accept photos of nutrition labels (optional)
	 */

	interface CaptureResult {
		foodImage: Blob;
		labelImage?: Blob; // Optional nutrition label image (Req 7.1)
		source: 'camera' | 'gallery';
	}

	interface Props {
		onCapture: (result: CaptureResult) => void;
		onCancel?: () => void;
	}

	let { onCapture, onCancel }: Props = $props();

	let videoRef: HTMLVideoElement | null = $state(null);
	let canvasRef: HTMLCanvasElement | null = $state(null);
	let fileInputRef: HTMLInputElement | null = $state(null);
	let labelFileInputRef: HTMLInputElement | null = $state(null);
	let stream: MediaStream | null = $state(null);
	let error: string | null = $state(null);
	let isCameraActive = $state(false);

	// Label capture state
	let foodImage: Blob | null = $state(null);
	let labelImage: Blob | null = $state(null);
	let captureSource: 'camera' | 'gallery' = $state('camera');
	let showLabelOption = $state(false); // Show after food photo captured

	async function startCamera() {
		error = null;
		try {
			// Req 1.1: Use rear-facing camera
			stream = await navigator.mediaDevices.getUserMedia({
				video: {
					facingMode: { ideal: 'environment' },
					width: { ideal: 1920 },
					height: { ideal: 1080 }
				}
			});
			if (videoRef) {
				videoRef.srcObject = stream;
				await videoRef.play();
				isCameraActive = true;
			}
		} catch (e) {
			// Camera access denied or unavailable - show gallery option
			error = 'Camera unavailable. Use gallery to upload a photo.';
			isCameraActive = false;
		}
	}

	function stopCamera() {
		if (stream) {
			stream.getTracks().forEach((track) => track.stop());
			stream = null;
		}
		isCameraActive = false;
	}

	function capturePhoto() {
		if (!videoRef || !canvasRef) return;

		const ctx = canvasRef.getContext('2d');
		if (!ctx) return;

		canvasRef.width = videoRef.videoWidth;
		canvasRef.height = videoRef.videoHeight;
		ctx.drawImage(videoRef, 0, 0);

		// Req 1.2: Output as JPEG
		canvasRef.toBlob(
			(blob) => {
				if (blob) {
					stopCamera();
					// Store food image and show label option
					foodImage = blob;
					captureSource = 'camera';
					showLabelOption = true;
				}
			},
			'image/jpeg',
			0.9
		);
	}

	/**
	 * Capture label photo from camera.
	 */
	function captureLabelPhoto() {
		if (!videoRef || !canvasRef) return;

		const ctx = canvasRef.getContext('2d');
		if (!ctx) return;

		canvasRef.width = videoRef.videoWidth;
		canvasRef.height = videoRef.videoHeight;
		ctx.drawImage(videoRef, 0, 0);

		canvasRef.toBlob(
			(blob) => {
				if (blob) {
					stopCamera();
					labelImage = blob;
					// Complete capture with both images
					completeCapture();
				}
			},
			'image/jpeg',
			0.9
		);
	}

	function handleFileSelect(event: Event) {
		const input = event.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		// Req 1.2: Accept JPEG and PNG only
		if (!['image/jpeg', 'image/png'].includes(file.type)) {
			error = 'Please select a JPEG or PNG image.';
			return;
		}

		error = null;
		// Store food image and show label option
		foodImage = file;
		captureSource = 'gallery';
		showLabelOption = true;
	}

	/**
	 * Handle label image selection from gallery.
	 */
	function handleLabelFileSelect(event: Event) {
		const input = event.target as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		// Req 1.2: Accept JPEG and PNG only
		if (!['image/jpeg', 'image/png'].includes(file.type)) {
			error = 'Please select a JPEG or PNG image for the label.';
			return;
		}

		error = null;
		labelImage = file;
		completeCapture();
	}

	/**
	 * Complete capture and call onCapture with both images.
	 */
	function completeCapture() {
		if (!foodImage) return;

		// Build result object, only including labelImage if it exists
		const result: CaptureResult = {
			foodImage,
			source: captureSource
		};
		if (labelImage) {
			result.labelImage = labelImage;
		}
		onCapture(result);

		// Reset state
		foodImage = null;
		labelImage = null;
		showLabelOption = false;
	}

	/**
	 * Skip label capture and proceed with food image only.
	 */
	function skipLabel() {
		completeCapture();
	}

	/**
	 * Start camera for label capture.
	 */
	async function startLabelCamera() {
		await startCamera();
	}

	/**
	 * Open gallery for label selection.
	 */
	function openLabelGallery() {
		labelFileInputRef?.click();
	}

	function openGallery() {
		fileInputRef?.click();
	}

	function handleCancel() {
		stopCamera();
		// Reset label capture state
		foodImage = null;
		labelImage = null;
		showLabelOption = false;
		onCancel?.();
	}

	/**
	 * Go back from label capture to food capture.
	 */
	function handleLabelBack() {
		stopCamera();
		foodImage = null;
		labelImage = null;
		showLabelOption = false;
	}

	// Cleanup on unmount
	$effect(() => {
		return () => {
			stopCamera();
		};
	});
</script>

<div class="flex flex-col gap-4">
	{#if error}
		<div class="rounded-lg bg-red-900/50 px-4 py-3 text-sm text-red-200">
			{error}
		</div>
	{/if}

	{#if showLabelOption && !isCameraActive}
		<!-- Label option screen - after food photo captured -->
		<div class="flex flex-col gap-4">
			<!-- Food image preview thumbnail -->
			{#if foodImage}
				<div class="relative overflow-hidden rounded-lg bg-black/50">
					<img
						src={URL.createObjectURL(foodImage)}
						alt="Captured food"
						class="w-full h-48 object-cover opacity-70"
					/>
					<div class="absolute inset-0 flex items-center justify-center">
						<span class="rounded-full bg-brand-accent/90 px-3 py-1 text-sm font-medium text-black">
							Food photo captured
						</span>
					</div>
				</div>
			{/if}

			<p class="text-center text-white/80 text-sm">
				Is this a packaged food? Add a nutrition label photo for more accurate macros.
			</p>

			<div class="flex flex-col gap-3">
				<button
					onclick={startLabelCamera}
					class="w-full rounded-lg bg-white/10 py-4 text-lg font-semibold text-white min-h-[44px] flex items-center justify-center gap-2"
				>
					<svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"></path>
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"></path>
					</svg>
					Add Label Photo
				</button>
				<button
					onclick={openLabelGallery}
					class="w-full rounded-lg bg-white/10 py-4 text-lg font-semibold text-white min-h-[44px] flex items-center justify-center gap-2"
				>
					<svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
					</svg>
					Choose Label from Gallery
				</button>
				<button
					onclick={skipLabel}
					class="w-full rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px]"
				>
					Continue Without Label
				</button>
				<button
					onclick={handleLabelBack}
					class="w-full rounded-lg border border-white/20 py-4 text-lg font-semibold text-white/70 min-h-[44px]"
				>
					Retake Food Photo
				</button>
			</div>
		</div>

		<!-- Hidden file input for label gallery selection -->
		<input
			bind:this={labelFileInputRef}
			type="file"
			accept="image/jpeg,image/png"
			onchange={handleLabelFileSelect}
			class="hidden"
		/>
	{:else if isCameraActive && showLabelOption}
		<!-- Label camera active -->
		<div class="relative overflow-hidden rounded-lg bg-black">
			<video bind:this={videoRef} class="w-full" autoplay playsinline muted></video>
			<canvas bind:this={canvasRef} class="hidden"></canvas>
			<!-- Label camera indicator -->
			<div class="absolute top-2 left-2 rounded-full bg-white/20 px-3 py-1 text-xs text-white">
				Capturing label
			</div>
		</div>

		<!-- Label camera controls -->
		<div class="flex gap-3">
			<button
				onclick={captureLabelPhoto}
				class="flex-1 rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px]"
			>
				Take Label Photo
			</button>
			<button
				onclick={() => { stopCamera(); }}
				class="rounded-lg bg-white/10 px-6 py-4 text-lg font-semibold text-white min-h-[44px]"
			>
				Cancel
			</button>
		</div>
	{:else if isCameraActive}
		<!-- Food camera preview -->
		<div class="relative overflow-hidden rounded-lg bg-black">
			<video bind:this={videoRef} class="w-full" autoplay playsinline muted></video>
			<canvas bind:this={canvasRef} class="hidden"></canvas>
		</div>

		<!-- Food camera controls -->
		<div class="flex gap-3">
			<button
				onclick={capturePhoto}
				class="flex-1 rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px]"
			>
				Take Photo
			</button>
			<button
				onclick={handleCancel}
				class="rounded-lg bg-white/10 px-6 py-4 text-lg font-semibold text-white min-h-[44px]"
			>
				Cancel
			</button>
		</div>
	{:else}
		<!-- Initial state - choose camera or gallery -->
		<div class="flex flex-col gap-3">
			<button
				onclick={startCamera}
				class="w-full rounded-lg bg-brand-accent py-4 text-lg font-semibold text-black min-h-[44px]"
			>
				Open Camera
			</button>
			<button
				onclick={openGallery}
				class="w-full rounded-lg bg-white/10 py-4 text-lg font-semibold text-white min-h-[44px]"
			>
				Choose from Gallery
			</button>
			{#if onCancel}
				<button
					onclick={handleCancel}
					class="w-full rounded-lg border border-white/20 py-4 text-lg font-semibold text-white/70 min-h-[44px]"
				>
					Cancel
				</button>
			{/if}
		</div>

		<!-- Hidden file input for gallery selection -->
		<!-- Req 1.2: Accept JPEG and PNG only -->
		<input
			bind:this={fileInputRef}
			type="file"
			accept="image/jpeg,image/png"
			onchange={handleFileSelect}
			class="hidden"
		/>
	{/if}
</div>
