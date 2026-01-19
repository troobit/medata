<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    title: string;
    description?: string;
    icon?: Snippet;
    action?: Snippet;
  }

  let { title, description, icon, action }: Props = $props();
</script>

<div class="flex flex-col items-center justify-center py-12 px-4 text-center">
  {#if icon}
    <div class="mb-4 text-gray-500">
      {@render icon()}
    </div>
  {/if}

  <h3 class="text-lg font-medium text-gray-200">{title}</h3>

  {#if description}
    <p class="mt-2 text-sm text-gray-400 max-w-sm">{description}</p>
  {/if}

  {#if action}
    <div class="mt-6">
      {@render action()}
    </div>
  {/if}
</div>
