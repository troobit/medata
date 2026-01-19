<script lang="ts">
  interface Props {
    class?: string;
  }

  let { class: className = 'h-6 w-6' }: Props = $props();
</script>

<!-- Blood drop/BSL icon -->
<svg
  class={className}
  fill="none"
  stroke="currentColor"
  viewBox="0 0 24 24"
  aria-hidden="true"
>
  <!-- Blood drop shape -->
  <path
    stroke-linecap="round"
    stroke-linejoin="round"
    stroke-width="2"
    d="M12 3c-3.5 4.5-6 7.5-6 11a6 6 0 1012 0c0-3.5-2.5-6.5-6-11z"
  />
  <!-- Glucose reading lines -->
  <path
    stroke-linecap="round"
    stroke-width="2"
    d="M9 13h6M9 16h4"
  />
</svg>
