<script lang="ts">
  /**
   * ReferenceCardGuide - Guide overlay for positioning a reference card in frame.
   * Shows a credit card outline with alignment guides.
   */
  import type { ReferenceObjectType } from '$lib/types/local-estimation';

  interface Props {
    referenceType?: ReferenceObjectType;
    detected?: boolean;
    confidence?: number;
  }

  let { referenceType = 'credit-card', detected = false, confidence = 0 }: Props = $props();

  // Card aspect ratio for credit card
  const cardAspectRatio = 85.6 / 53.98;

  // Determine colors based on detection state
  const borderColor = $derived(
    detected
      ? confidence > 0.7
        ? 'border-green-500'
        : 'border-yellow-500'
      : 'border-white/50'
  );

  const bgColor = $derived(
    detected ? (confidence > 0.7 ? 'bg-green-500/10' : 'bg-yellow-500/10') : 'bg-transparent'
  );
</script>

<div class="pointer-events-none absolute inset-0 flex items-center justify-center">
  <!-- Guide container -->
  <div class="relative w-3/4 max-w-64">
    {#if referenceType === 'credit-card'}
      <!-- Credit card outline -->
      <div
        class="relative rounded-lg border-2 border-dashed transition-colors duration-300 {borderColor} {bgColor}"
        style="aspect-ratio: {cardAspectRatio};"
      >
        <!-- Corner markers -->
        <div class="absolute -left-1 -top-1 h-4 w-4 border-l-2 border-t-2 {borderColor}"></div>
        <div class="absolute -right-1 -top-1 h-4 w-4 border-r-2 border-t-2 {borderColor}"></div>
        <div class="absolute -bottom-1 -left-1 h-4 w-4 border-b-2 border-l-2 {borderColor}"></div>
        <div class="absolute -bottom-1 -right-1 h-4 w-4 border-b-2 border-r-2 {borderColor}"></div>

        <!-- Center crosshair -->
        <div class="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
          <div class="h-6 w-px bg-white/30"></div>
          <div class="absolute left-1/2 top-1/2 h-px w-6 -translate-x-1/2 -translate-y-1/2 bg-white/30"></div>
        </div>

        <!-- Card chip indicator -->
        <div
          class="absolute left-3 top-1/2 h-5 w-7 -translate-y-1/2 rounded border border-white/30"
        ></div>
      </div>

      <!-- Instructions -->
      <p class="mt-3 text-center text-sm text-white/80">
        {#if detected}
          {#if confidence > 0.7}
            Card detected
          {:else}
            Align card more clearly
          {/if}
        {:else}
          Place card next to food
        {/if}
      </p>
    {:else if referenceType === 'coin-au-dollar' || referenceType === 'coin-au-50c'}
      <!-- Coin outline -->
      <div class="flex justify-center">
        <div
          class="h-16 w-16 rounded-full border-2 border-dashed transition-colors duration-300 {borderColor} {bgColor}"
        >
          <!-- Center dot -->
          <div class="absolute left-1/2 top-1/2 h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white/30"></div>
        </div>
      </div>

      <p class="mt-3 text-center text-sm text-white/80">
        {#if detected}
          Coin detected
        {:else}
          Place {referenceType === 'coin-au-dollar' ? '$1' : '50c'} coin next to food
        {/if}
      </p>
    {/if}
  </div>
</div>
