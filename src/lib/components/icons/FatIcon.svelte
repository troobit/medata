<script lang="ts">
  interface Props {
    class?: string;
  }

  let { class: className = 'h-6 w-6' }: Props = $props();
</script>

<!-- Oil drop/Fat icon -->
<svg class={className} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
  <!-- Oil drop shape -->
  <path
    stroke-linecap="round"
    stroke-linejoin="round"
    stroke-width="2"
    d="M12 3c-4 5-7 8-7 12a7 7 0 1014 0c0-4-3-7-7-12z"
  />
  <!-- Shine highlight -->
  <path stroke-linecap="round" stroke-width="1.5" d="M9 14c0-1.5 1-3 3-4" />
</svg>
