<script lang="ts">
  interface Props {
    onImageSelect: (base64: string, file: File) => void;
    class?: string;
  }

  let { onImageSelect, class: className = '' }: Props = $props();

  let isDragging = $state(false);
  let previewUrl = $state<string | null>(null);
  let fileInputRef: HTMLInputElement;

  function handleDragOver(e: DragEvent) {
    e.preventDefault();
    isDragging = true;
  }

  function handleDragLeave(e: DragEvent) {
    e.preventDefault();
    isDragging = false;
  }

  function handleDrop(e: DragEvent) {
    e.preventDefault();
    isDragging = false;

    const file = e.dataTransfer?.files[0];
    if (file && file.type.startsWith('image/')) {
      processFile(file);
    }
  }

  function handleFileInput(e: Event) {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (file) {
      processFile(file);
    }
  }

  function processFile(file: File) {
    const reader = new FileReader();
    reader.onload = () => {
      const dataUrl = reader.result as string;
      previewUrl = dataUrl;

      // Extract base64 without the data URL prefix
      const base64 = dataUrl.split(',')[1];
      onImageSelect(base64, file);
    };
    reader.readAsDataURL(file);
  }

  function triggerFileInput() {
    fileInputRef?.click();
  }

  function clearPreview() {
    previewUrl = null;
    if (fileInputRef) {
      fileInputRef.value = '';
    }
  }
</script>

<div class={className}>
  {#if previewUrl}
    <div class="relative">
      <img
        src={previewUrl}
        alt="Screenshot preview"
        class="w-full rounded-lg border border-gray-700"
      />
      <button
        type="button"
        onclick={clearPreview}
        class="absolute right-2 top-2 rounded-full bg-gray-900/80 p-2 text-gray-300 hover:bg-gray-800 hover:text-white"
        aria-label="Remove image"
      >
        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M6 18L18 6M6 6l12 12"
          />
        </svg>
      </button>
    </div>
  {:else}
    <button
      type="button"
      onclick={triggerFileInput}
      ondragover={handleDragOver}
      ondragleave={handleDragLeave}
      ondrop={handleDrop}
      class="w-full rounded-xl border-2 border-dashed p-8 text-center transition-colors
        {isDragging
        ? 'border-brand-accent bg-brand-accent/10'
        : 'border-gray-600 hover:border-gray-500 hover:bg-gray-800/50'}"
    >
      <svg
        class="mx-auto h-12 w-12 text-gray-500"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
        />
      </svg>
      <p class="mt-4 text-gray-300">
        {isDragging ? 'Drop image here' : 'Tap to upload or drag & drop'}
      </p>
      <p class="mt-1 text-sm text-gray-500">CGM screenshot (Libre, Dexcom, etc.)</p>
    </button>
  {/if}

  <input
    bind:this={fileInputRef}
    type="file"
    accept="image/*"
    onchange={handleFileInput}
    class="hidden"
  />
</div>
