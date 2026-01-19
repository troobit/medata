<script lang="ts">
  interface Props {
    class?: string;
  }

  let { class: className = 'h-6 w-6' }: Props = $props();
</script>

<!-- Wine glass/Alcohol icon -->
<svg
  class={className}
  fill="none"
  stroke="currentColor"
  viewBox="0 0 24 24"
  aria-hidden="true"
>
  <!-- Glass bowl -->
  <path
    stroke-linecap="round"
    stroke-linejoin="round"
    stroke-width="2"
    d="M8 3h8l-1 8a4 4 0 01-3 3.87V18"
  />
  <!-- Wine level -->
  <path
    stroke-linecap="round"
    stroke-width="1.5"
    d="M9 7h6"
  />
  <!-- Stem -->
  <path
    stroke-linecap="round"
    stroke-width="2"
    d="M12 15v3"
  />
  <!-- Base -->
  <path
    stroke-linecap="round"
    stroke-width="2"
    d="M8 21h8"
  />
</svg>
