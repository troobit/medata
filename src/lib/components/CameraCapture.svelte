<script lang="ts">
	/**
	 * CameraCapture component for capturing food photos.
	 * Req 1.1: Use rear-facing camera via MediaDevices API
	 * Req 1.2: Accept JPEG and PNG only
	 * Req 1.5: Mobile-first
	 * Req 1.6: Gallery upload fallback via file input
	 */

	interface CaptureResult {
		foodImage: Blob;
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
	let stream: MediaStream | null = $state(null);
	let error: string | null = $state(null);
	let isCameraActive = $state(false);

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
					onCapture({ foodImage: blob, source: 'camera' });
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
		onCapture({ foodImage: file, source: 'gallery' });
	}

	function openGallery() {
		fileInputRef?.click();
	}

	function handleCancel() {
		stopCamera();
		onCancel?.();
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

	{#if isCameraActive}
		<!-- Camera preview -->
		<div class="relative overflow-hidden rounded-lg bg-black">
			<video bind:this={videoRef} class="w-full" autoplay playsinline muted></video>
			<canvas bind:this={canvasRef} class="hidden"></canvas>
		</div>

		<!-- Camera controls -->
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
