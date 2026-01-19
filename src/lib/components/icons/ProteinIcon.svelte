<script lang="ts">
  interface Props {
    class?: string;
  }

  let { class: className = 'h-6 w-6' }: Props = $props();
</script>

<!-- Meat/Protein icon (drumstick) -->
<svg class={className} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
  <!-- Drumstick meat -->
  <path
    stroke-linecap="round"
    stroke-linejoin="round"
    stroke-width="2"
    d="M15.5 4.5a4 4 0 00-5.66 5.66l-5.66 5.66a2 2 0 102.83 2.83l5.66-5.66a4 4 0 005.66-5.66"
  />
  <!-- Bone end -->
  <circle cx="17" cy="7" r="1.5" stroke-width="2" />
</svg>
