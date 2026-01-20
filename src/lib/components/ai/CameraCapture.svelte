<script lang="ts">
  /**
   * Camera Capture Component
   * Workstream A: AI-Powered Food Recognition
   *
   * Provides camera access for taking food photos or selecting from gallery.
   */

  interface Props {
    onCapture: (blob: Blob) => void;
    onCancel?: () => void;
  }

  let { onCapture, onCancel }: Props = $props();

  let videoElement = $state<HTMLVideoElement | null>(null);
  let canvasElement = $state<HTMLCanvasElement | null>(null);
  let stream = $state<MediaStream | null>(null);
  let error = $state<string | null>(null);
  let cameraActive = $state(false);
  let facingMode = $state<'environment' | 'user'>('environment');

  async function startCamera() {
    error = null;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: facingMode,
          width: { ideal: 1920 },
          height: { ideal: 1080 }
        }
      });
      if (videoElement) {
        videoElement.srcObject = stream;
        cameraActive = true;
      }
    } catch (e) {
      if (e instanceof DOMException) {
        if (e.name === 'NotAllowedError') {
          error = 'Camera access denied. Please enable camera permissions.';
        } else if (e.name === 'NotFoundError') {
          error = 'No camera found on this device.';
        } else {
          error = `Camera error: ${e.message}`;
        }
      } else {
        error = 'Failed to access camera';
      }
    }
  }

  function stopCamera() {
    if (stream) {
      stream.getTracks().forEach((track) => track.stop());
      stream = null;
    }
    cameraActive = false;
  }

  function switchCamera() {
    stopCamera();
    facingMode = facingMode === 'environment' ? 'user' : 'environment';
    startCamera();
  }

  function capturePhoto() {
    if (!videoElement || !canvasElement) return;

    const canvas = canvasElement;
    const video = videoElement;

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    ctx.drawImage(video, 0, 0);

    canvas.toBlob(
      (blob) => {
        if (blob) {
          stopCamera();
          onCapture(blob);
        }
      },
      'image/jpeg',
      0.9
    );
  }

  function handleFileSelect(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      onCapture(file);
    }
  }

  function handleCancel() {
    stopCamera();
    onCancel?.();
  }

  $effect(() => {
    return () => {
      stopCamera();
    };
  });
</script>

<div class="flex flex-col">
  {#if error}
    <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-center text-red-400">
      {error}
    </div>
  {/if}

  {#if cameraActive}
    <!-- Camera Preview -->
    <div class="relative mb-4 overflow-hidden rounded-lg bg-black">
      <video bind:this={videoElement} autoplay playsinline muted class="h-64 w-full object-cover"
      ></video>

      <!-- Camera Controls Overlay -->
      <div class="absolute bottom-4 left-0 right-0 flex items-center justify-center gap-4">
        <button
          type="button"
          onclick={handleCancel}
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800/80 text-white"
          aria-label="Cancel"
        >
          <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>

        <button
          type="button"
          onclick={capturePhoto}
          class="flex h-16 w-16 items-center justify-center rounded-full bg-white"
          aria-label="Take photo"
        >
          <div class="h-14 w-14 rounded-full border-4 border-gray-900"></div>
        </button>

        <button
          type="button"
          onclick={switchCamera}
          class="flex h-12 w-12 items-center justify-center rounded-full bg-gray-800/80 text-white"
          aria-label="Switch camera"
        >
          <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
        </button>
      </div>
    </div>

    <canvas bind:this={canvasElement} class="hidden"></canvas>
  {:else}
    <!-- Capture Options -->
    <div class="grid grid-cols-2 gap-3">
      <button
        type="button"
        onclick={startCamera}
        class="flex flex-col items-center justify-center rounded-lg bg-blue-500/10 p-6 transition-colors hover:bg-blue-500/20"
      >
        <svg
          class="mb-2 h-10 w-10 text-blue-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z"
          />
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M15 13a3 3 0 11-6 0 3 3 0 016 0z"
          />
        </svg>
        <span class="text-sm font-medium text-blue-400">Take Photo</span>
      </button>

      <label
        class="flex cursor-pointer flex-col items-center justify-center rounded-lg bg-purple-500/10 p-6 transition-colors hover:bg-purple-500/20"
      >
        <svg
          class="mb-2 h-10 w-10 text-purple-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
          />
        </svg>
        <span class="text-sm font-medium text-purple-400">From Gallery</span>
        <input type="file" accept="image/*" class="hidden" onchange={handleFileSelect} />
      </label>
    </div>

    {#if onCancel}
      <button
        type="button"
        onclick={handleCancel}
        class="mt-4 w-full rounded-lg bg-gray-800 py-3 text-center text-gray-400 transition-colors hover:bg-gray-700"
      >
        Cancel
      </button>
    {/if}
  {/if}
</div>
