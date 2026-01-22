<script lang="ts">
  /**
   * CGM Image Capture Component
   *
   * Handles image upload/capture for CGM graph screenshots.
   * Supports file selection and camera capture.
   */

  interface Props {
    onImageSelected: (file: File, previewUrl: string) => void;
    disabled?: boolean;
  }

  let { onImageSelected, disabled = false }: Props = $props();

  let fileInput = $state<HTMLInputElement | null>(null);
  let dragOver = $state(false);

  function handleFileSelect(event: Event) {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      processFile(file);
    }
  }

  function handleDrop(event: DragEvent) {
    event.preventDefault();
    dragOver = false;

    const file = event.dataTransfer?.files?.[0];
    if (file && file.type.startsWith('image/')) {
      processFile(file);
    }
  }

  function handleDragOver(event: DragEvent) {
    event.preventDefault();
    dragOver = true;
  }

  function handleDragLeave() {
    dragOver = false;
  }

  function processFile(file: File) {
    if (!file.type.startsWith('image/')) {
      return;
    }

    const previewUrl = URL.createObjectURL(file);
    onImageSelected(file, previewUrl);
  }

  function triggerFileInput() {
    fileInput?.click();
  }
</script>

<div
  class="relative rounded-xl border-2 border-dashed transition-colors {dragOver
    ? 'border-brand-accent bg-brand-accent/10'
    : 'border-gray-700 bg-gray-900/50'} {disabled ? 'opacity-50 cursor-not-allowed' : ''}"
  role="button"
  tabindex={disabled ? -1 : 0}
  ondrop={handleDrop}
  ondragover={handleDragOver}
  ondragleave={handleDragLeave}
  onclick={() => !disabled && triggerFileInput()}
  onkeypress={(e) => e.key === 'Enter' && !disabled && triggerFileInput()}
>
  <input
    bind:this={fileInput}
    type="file"
    accept="image/*"
    capture="environment"
    class="hidden"
    onchange={handleFileSelect}
    {disabled}
  />

  <div class="flex flex-col items-center justify-center px-6 py-12">
    <!-- Camera Icon -->
    <div class="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-gray-800 text-3xl">
      <svg class="h-8 w-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
    </div>

    <p class="mb-2 text-center text-lg font-medium text-white">
      {dragOver ? 'Drop image here' : 'Upload CGM Screenshot'}
    </p>

    <p class="mb-4 text-center text-sm text-gray-400">Take a photo or select from gallery</p>

    <div class="flex gap-4">
      <button
        type="button"
        class="rounded-lg bg-brand-accent px-4 py-2 text-sm font-medium text-gray-950 transition-colors hover:bg-brand-accent/90"
        onclick={(e) => {
          e.stopPropagation();
          triggerFileInput();
        }}
        {disabled}
      >
        Choose Image
      </button>
    </div>

    <p class="mt-4 text-xs text-gray-500">Supports Freestyle Libre, Dexcom G6/G7, Medtronic</p>
  </div>
</div>
