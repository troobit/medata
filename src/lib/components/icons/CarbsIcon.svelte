<script lang="ts">
  interface Props {
    class?: string;
  }

  let { class: className = 'h-6 w-6' }: Props = $props();
</script>

<!-- Bread/Carbs icon -->
<svg
  class={className}
  fill="none"
  stroke="currentColor"
  viewBox="0 0 24 24"
  aria-hidden="true"
>
  <!-- Bread loaf shape -->
  <path
    stroke-linecap="round"
    stroke-linejoin="round"
    stroke-width="2"
    d="M4 12c0-3 2-5 8-5s8 2 8 5v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5z"
  />
  <!-- Top crust line -->
  <path
    stroke-linecap="round"
    stroke-width="2"
    d="M7 10c2-1 8-1 10 0"
  />
  <!-- Slice lines -->
  <path
    stroke-linecap="round"
    stroke-width="1.5"
    d="M9 12v5M12 12v5M15 12v5"
  />
</svg>
