<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    variant?: 'primary' | 'secondary' | 'ghost';
    size?: 'sm' | 'md' | 'lg';
    loading?: boolean;
    disabled?: boolean;
    href?: string;
    type?: 'button' | 'submit' | 'reset';
    class?: string;
    onclick?: () => void;
    children: Snippet;
  }

  let {
    variant = 'primary',
    size = 'md',
    loading = false,
    disabled = false,
    href,
    type = 'button',
    class: className = '',
    onclick,
    children
  }: Props = $props();

  const baseClasses =
    'inline-flex items-center justify-center font-medium rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-gray-950 disabled:opacity-50 disabled:cursor-not-allowed';

  const variantClasses = {
    primary: 'bg-brand-accent text-gray-950 hover:bg-brand-accent/90 focus:ring-brand-accent',
    secondary:
      'bg-gray-800 text-gray-100 hover:bg-gray-700 focus:ring-gray-600 border border-gray-700',
    ghost: 'text-gray-300 hover:bg-gray-800 hover:text-white focus:ring-gray-600'
  };

  const sizeClasses = {
    sm: 'text-sm px-3 py-1.5 min-h-[32px]',
    md: 'text-base px-4 py-2 min-h-[44px]',
    lg: 'text-lg px-6 py-3 min-h-[52px]'
  };
</script>

{#if href}
  <a
    {href}
    class="{baseClasses} {variantClasses[variant]} {sizeClasses[size]} {className}"
  >
    {#if loading}
      <span
        class="mr-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
      ></span>
    {/if}
    {@render children()}
  </a>
{:else}
  <button
    {type}
    class="{baseClasses} {variantClasses[variant]} {sizeClasses[size]} {className}"
    disabled={disabled || loading}
    {onclick}
  >
    {#if loading}
      <span
        class="mr-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
      ></span>
    {/if}
    {@render children()}
  </button>
{/if}
