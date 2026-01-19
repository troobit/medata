<script lang="ts">
  interface Props {
    class?: string;
  }

  let { class: className = 'h-6 w-6' }: Props = $props();
</script>

<!-- Syringe/Needle icon -->
<svg
  class={className}
  fill="none"
  stroke="currentColor"
  viewBox="0 0 24 24"
  aria-hidden="true"
>
  <!-- Needle tip -->
  <path
    stroke-linecap="round"
    stroke-linejoin="round"
    stroke-width="2"
    d="M4 20l3-3"
  />
  <!-- Syringe barrel -->
  <rect
    x="7"
    y="7"
    width="10"
    height="6"
    rx="1"
    transform="rotate(45 12 10)"
    stroke-width="2"
  />
  <!-- Plunger handle -->
  <path
    stroke-linecap="round"
    stroke-linejoin="round"
    stroke-width="2"
    d="M17 7l3-3M18.5 5.5l1.5-1.5"
  />
  <!-- Measurement marks -->
  <path
    stroke-linecap="round"
    stroke-width="1.5"
    d="M10 11l1-1M12 13l1-1"
  />
</svg>
