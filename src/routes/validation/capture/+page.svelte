<script lang="ts">
  /**
   * Test Data Capture Page
   * Admin mode for capturing food images with verified macro data
   */
  import { goto } from '$app/navigation';
  import { CameraCapture, PhotoPreview } from '$lib/components/ai';
  import { Button, Input } from '$lib/components/ui';
  import { validationStore } from '$lib/stores';
  import { compressImage, blobToDataUrl } from '$lib/utils/imageProcessing';
  import type { FoodCategory, GroundTruthSource, MacroData } from '$lib/types';

  // Flow states
  type FlowState = 'capture' | 'preview' | 'form';
  let flowState = $state<FlowState>('capture');

  // Image state
  let capturedImage = $state<Blob | null>(null);
  let imageUrl = $state<string | null>(null);

  // Form state
  let description = $state('');
  let category = $state<FoodCategory>('other');
  let source = $state<GroundTruthSource>('manual-weighed');
  let sourceReference = $state('');

  // Ground truth macros
  let carbs = $state(0);
  let protein = $state(0);
  let fat = $state(0);
  let calories = $state(0);

  // Items (optional breakdown)
  let items = $state<Array<{ name: string; quantity: number; unit: string; macros: Partial<MacroData> }>>([]);
  let showItems = $state(false);
  let newItemName = $state('');
  let newItemQuantity = $state(0);
  let newItemUnit = $state('g');

  // UI state
  let saving = $state(false);
  let error = $state<string | null>(null);

  const categories: Array<{ value: FoodCategory; label: string }> = [
    { value: 'grain', label: 'Grain/Bread' },
    { value: 'protein', label: 'Protein/Meat' },
    { value: 'vegetable', label: 'Vegetable' },
    { value: 'fruit', label: 'Fruit' },
    { value: 'dairy', label: 'Dairy' },
    { value: 'fat', label: 'Fat/Oil' },
    { value: 'beverage', label: 'Beverage' },
    { value: 'mixed', label: 'Mixed Dish' },
    { value: 'snack', label: 'Snack' },
    { value: 'other', label: 'Other' }
  ];

  const sources: Array<{ value: GroundTruthSource; label: string; description: string }> = [
    { value: 'manual-weighed', label: 'Weighed', description: 'Manually weighed on scale' },
    { value: 'nutrition-label', label: 'Label', description: 'From nutrition label' },
    { value: 'usda', label: 'USDA', description: 'USDA FoodData Central' },
    { value: 'academic', label: 'Academic', description: 'Research publication' },
    { value: 'imported', label: 'Imported', description: 'External dataset' }
  ];

  async function handleCapture(blob: Blob) {
    error = null;
    try {
      capturedImage = await compressImage(blob, {
        maxWidth: 1024,
        maxHeight: 1024,
        quality: 0.85,
        format: 'image/jpeg'
      });
      imageUrl = await blobToDataUrl(capturedImage);
      flowState = 'preview';
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to process image';
    }
  }

  function handleRetake() {
    capturedImage = null;
    imageUrl = null;
    flowState = 'capture';
    error = null;
  }

  function handleConfirm() {
    flowState = 'form';
  }

  function addItem() {
    if (!newItemName.trim()) return;
    items = [
      ...items,
      {
        name: newItemName.trim(),
        quantity: newItemQuantity,
        unit: newItemUnit,
        macros: {}
      }
    ];
    newItemName = '';
    newItemQuantity = 0;
  }

  function removeItem(index: number) {
    items = items.filter((_, i) => i !== index);
  }

  async function handleSave() {
    if (!imageUrl) {
      error = 'No image captured';
      return;
    }

    if (carbs === 0 && protein === 0 && fat === 0 && calories === 0) {
      error = 'Please enter at least one nutritional value';
      return;
    }

    saving = true;
    error = null;

    try {
      const groundTruth: MacroData = {
        carbs,
        protein,
        fat,
        calories
      };

      await validationStore.createTestEntry({
        imageUrl,
        groundTruth,
        category,
        description: description.trim() || undefined,
        source,
        sourceReference: sourceReference.trim() || undefined,
        items: items.length > 0 ? items : undefined
      });

      goto('/validation');
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to save test entry';
    } finally {
      saving = false;
    }
  }

  function handleCancel() {
    goto('/validation');
  }

  // Calculate calories from macros (estimate)
  function calculateCalories() {
    // Carbs: 4 cal/g, Protein: 4 cal/g, Fat: 9 cal/g
    calories = Math.round(carbs * 4 + protein * 4 + fat * 9);
  }

  // Page title
  let pageTitle = $derived.by(() => {
    switch (flowState) {
      case 'capture':
        return 'Capture Test Image';
      case 'preview':
        return 'Review Image';
      case 'form':
        return 'Enter Ground Truth';
      default:
        return 'Add Test Data';
    }
  });

  // Cleanup on unmount
  $effect(() => {
    return () => {
      if (imageUrl && !imageUrl.startsWith('data:')) {
        URL.revokeObjectURL(imageUrl);
      }
    };
  });
</script>

<svelte:head>
  <title>Add Test Data - MeData</title>
</svelte:head>

<div class="flex min-h-[calc(100dvh-80px)] flex-col px-4 py-6">
  <!-- Header -->
  <header class="mb-4">
    <div class="mb-4 flex items-center justify-between">
      {#if flowState === 'capture'}
        <a href="/validation" class="inline-flex items-center text-gray-400 hover:text-gray-200">
          <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          Back
        </a>
      {:else if flowState === 'preview'}
        <button
          type="button"
          class="inline-flex items-center text-gray-400 hover:text-gray-200"
          onclick={handleRetake}
        >
          <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          Retake
        </button>
      {:else}
        <button
          type="button"
          class="inline-flex items-center text-gray-400 hover:text-gray-200"
          onclick={() => (flowState = 'preview')}
        >
          <svg class="mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
          </svg>
          Back
        </button>
      {/if}

      <span class="rounded bg-purple-500/20 px-2 py-1 text-xs text-purple-400">
        Admin Mode
      </span>
    </div>

    <h1 class="text-xl font-bold text-white">{pageTitle}</h1>
    <p class="mt-1 text-sm text-gray-400">
      {#if flowState === 'capture'}
        Take a photo of food with known nutritional values
      {:else if flowState === 'preview'}
        Review the captured image
      {:else}
        Enter the verified nutritional information
      {/if}
    </p>
  </header>

  <!-- Error display -->
  {#if error}
    <div class="mb-4 rounded-lg bg-red-500/20 px-4 py-3 text-red-400">
      {error}
    </div>
  {/if}

  <!-- Main content -->
  <div class="flex flex-1 flex-col">
    {#if flowState === 'capture'}
      <CameraCapture onCapture={handleCapture} onCancel={handleCancel} />

    {:else if flowState === 'preview' && capturedImage}
      <PhotoPreview
        image={capturedImage}
        onConfirm={handleConfirm}
        onRetake={handleRetake}
        processing={false}
      />

    {:else if flowState === 'form'}
      <div class="flex flex-1 flex-col">
        <!-- Image thumbnail -->
        {#if imageUrl}
          <div class="mb-4 flex items-center gap-4">
            <img
              src={imageUrl}
              alt="Test food"
              class="h-20 w-20 rounded-lg object-cover"
            />
            <button
              type="button"
              class="text-sm text-gray-400 hover:text-gray-200"
              onclick={handleRetake}
            >
              Change image
            </button>
          </div>
        {/if}

        <!-- Ground Truth Macros -->
        <div class="mb-4 rounded-lg bg-gray-800/50 p-4">
          <h3 class="mb-3 font-semibold text-white">Ground Truth Values</h3>
          <p class="mb-3 text-xs text-gray-500">
            Enter the verified nutritional values for this food
          </p>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label for="carbs" class="mb-1 block text-xs font-medium text-green-400">Carbs (g)</label>
              <input
                id="carbs"
                type="number"
                bind:value={carbs}
                min="0"
                step="0.1"
                onchange={calculateCalories}
                class="w-full rounded-lg border border-gray-700 bg-gray-900 px-3 py-2 text-white focus:border-green-500 focus:outline-none"
              />
            </div>
            <div>
              <label for="protein" class="mb-1 block text-xs font-medium text-blue-400">Protein (g)</label>
              <input
                id="protein"
                type="number"
                bind:value={protein}
                min="0"
                step="0.1"
                onchange={calculateCalories}
                class="w-full rounded-lg border border-gray-700 bg-gray-900 px-3 py-2 text-white focus:border-blue-500 focus:outline-none"
              />
            </div>
            <div>
              <label for="fat" class="mb-1 block text-xs font-medium text-yellow-400">Fat (g)</label>
              <input
                id="fat"
                type="number"
                bind:value={fat}
                min="0"
                step="0.1"
                onchange={calculateCalories}
                class="w-full rounded-lg border border-gray-700 bg-gray-900 px-3 py-2 text-white focus:border-yellow-500 focus:outline-none"
              />
            </div>
            <div>
              <label for="calories" class="mb-1 block text-xs font-medium text-gray-400">Calories</label>
              <input
                id="calories"
                type="number"
                bind:value={calories}
                min="0"
                class="w-full rounded-lg border border-gray-700 bg-gray-900 px-3 py-2 text-white focus:border-gray-500 focus:outline-none"
              />
            </div>
          </div>
        </div>

        <!-- Metadata -->
        <div class="mb-4 space-y-3">
          <Input
            label="Description"
            bind:value={description}
            placeholder="e.g., 100g white rice, cooked"
          />

          <div>
            <label for="category" class="mb-1 block text-sm font-medium text-gray-400">Category</label>
            <select
              id="category"
              bind:value={category}
              class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-white focus:border-brand-accent focus:outline-none"
            >
              {#each categories as cat}
                <option value={cat.value}>{cat.label}</option>
              {/each}
            </select>
          </div>

          <div>
            <label for="source" class="mb-1 block text-sm font-medium text-gray-400">Data Source</label>
            <select
              id="source"
              bind:value={source}
              class="w-full rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-white focus:border-brand-accent focus:outline-none"
            >
              {#each sources as src}
                <option value={src.value}>{src.label} - {src.description}</option>
              {/each}
            </select>
          </div>

          {#if source === 'usda' || source === 'academic'}
            <Input
              label="Reference (optional)"
              bind:value={sourceReference}
              placeholder={source === 'usda' ? 'USDA FDC ID' : 'DOI or citation'}
            />
          {/if}
        </div>

        <!-- Food Items (optional) -->
        <div class="mb-4">
          <button
            type="button"
            class="mb-2 text-sm text-gray-400 hover:text-gray-200"
            onclick={() => (showItems = !showItems)}
          >
            {showItems ? '▼' : '►'} Add individual food items (optional)
          </button>

          {#if showItems}
            <div class="rounded-lg bg-gray-800/50 p-3">
              {#if items.length > 0}
                <div class="mb-3 space-y-2">
                  {#each items as item, index}
                    <div class="flex items-center justify-between rounded bg-gray-900 px-3 py-2">
                      <span class="text-sm text-white">
                        {item.quantity}{item.unit} {item.name}
                      </span>
                      <button
                        type="button"
                        onclick={() => removeItem(index)}
                        class="text-gray-500 hover:text-red-400"
                      >
                        ×
                      </button>
                    </div>
                  {/each}
                </div>
              {/if}

              <div class="flex gap-2">
                <input
                  type="number"
                  bind:value={newItemQuantity}
                  min="0"
                  step="0.1"
                  placeholder="Qty"
                  class="w-16 rounded bg-gray-900 px-2 py-1 text-sm text-white focus:outline-none"
                />
                <select
                  bind:value={newItemUnit}
                  class="rounded bg-gray-900 px-2 py-1 text-sm text-white focus:outline-none"
                >
                  <option value="g">g</option>
                  <option value="ml">ml</option>
                  <option value="piece">pc</option>
                  <option value="cup">cup</option>
                  <option value="tbsp">tbsp</option>
                </select>
                <input
                  type="text"
                  bind:value={newItemName}
                  placeholder="Food name"
                  class="flex-1 rounded bg-gray-900 px-2 py-1 text-sm text-white focus:outline-none"
                />
                <Button variant="secondary" size="sm" onclick={addItem}>
                  Add
                </Button>
              </div>
            </div>
          {/if}
        </div>

        <!-- Actions -->
        <div class="mt-auto grid grid-cols-2 gap-3 pt-4">
          <Button variant="secondary" onclick={handleCancel}>
            Cancel
          </Button>
          <Button variant="primary" onclick={handleSave} loading={saving}>
            Save Test Data
          </Button>
        </div>
      </div>
    {/if}
  </div>
</div>
