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
    onclick?: (event: MouseEvent) => void;
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
    'button-animated inline-flex items-center justify-center font-medium rounded-lg transition-all duration-300 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-gray-950 disabled:opacity-50 disabled:cursor-not-allowed relative overflow-hidden';

  const variantClasses = {
    primary:
      'btn-primary bg-brand-accent text-gray-950 hover:bg-brand-accent/90 hover:scale-105 hover:shadow-lg focus:ring-brand-accent',
    secondary:
      'btn-secondary bg-gray-800 text-gray-100 hover:bg-gray-700 hover:scale-105 hover:shadow-lg focus:ring-gray-600 border border-gray-700',
    ghost:
      'btn-ghost text-gray-300 hover:bg-gray-800 hover:text-white hover:scale-105 focus:ring-gray-600'
  };

  const sizeClasses = {
    sm: 'text-sm px-3 py-1.5 min-h-[32px]',
    md: 'text-base px-4 py-2 min-h-[44px]',
    lg: 'text-lg px-6 py-3 min-h-[52px]'
  };

  const classes = $derived(
    [baseClasses, variantClasses[variant], sizeClasses[size], className].join(' ')
  );

  // Ripple effect state
  let ripples = $state<Array<{ id: number; x: number; y: number }>>([]);
  let rippleId = 0;

  function createRipple(event: MouseEvent) {
    const button = event.currentTarget as HTMLElement;
    const rect = button.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;

    const id = rippleId++;
    ripples = [...ripples, { id, x, y }];

    setTimeout(() => {
      ripples = ripples.filter((r) => r.id !== id);
    }, 600);
  }

  function handleKeyDown(event: KeyboardEvent) {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      (event.currentTarget as HTMLAnchorElement).click();
    }
  }
</script>

{#if href}
  <a
    {href}
    class={classes}
    role="button"
    tabindex="0"
    onkeydown={handleKeyDown}
    onmousedown={createRipple}
  >
    <span class="button-content">
      {#if loading}
        <span
          class="mr-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
        ></span>
      {/if}
      {@render children()}
    </span>
    {#each ripples as ripple (ripple.id)}
      <span class="ripple" style="left: {ripple.x}px; top: {ripple.y}px;"></span>
    {/each}
  </a>
{:else}
  <button
    {type}
    class={classes}
    disabled={disabled || loading}
    onclick={(e) => onclick?.(e)}
    onmousedown={createRipple}
  >
    <span class="button-content">
      {#if loading}
        <span
          class="mr-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
        ></span>
      {/if}
      {@render children()}
    </span>
    {#each ripples as ripple (ripple.id)}
      <span class="ripple" style="left: {ripple.x}px; top: {ripple.y}px;"></span>
    {/each}
  </button>
{/if}

<style>
  .button-animated {
    transform-origin: center;
  }

  .button-animated:active {
    transform: scale(0.98);
  }

  .button-content {
    position: relative;
    z-index: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  /* Shimmer effect on hover */
  .button-animated::before {
    content: '';
    position: absolute;
    top: 0;
    left: -100%;
    width: 100%;
    height: 100%;
    background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.4), transparent);
    transition: left 0.5s ease;
    z-index: 0;
  }

  /* Adjust shimmer for secondary and ghost variants */
  .button-animated.btn-secondary::before,
  .button-animated.btn-ghost::before {
    background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.15), transparent);
  }

  .button-animated:hover::before {
    left: 100%;
  }

  /* Ripple effect */
  .ripple {
    position: absolute;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.5);
    width: 20px;
    height: 20px;
    margin-left: -10px;
    margin-top: -10px;
    animation: ripple-effect 0.6s ease-out;
    pointer-events: none;
    z-index: 0;
  }

  /* Adjust ripple for primary variant (dark text) */
  .btn-primary .ripple {
    background: rgba(0, 0, 0, 0.2);
  }

  @keyframes ripple-effect {
    from {
      transform: scale(0);
      opacity: 1;
    }
    to {
      transform: scale(20);
      opacity: 0;
    }
  }

  /* Respect reduced motion */
  @media (prefers-reduced-motion: reduce) {
    .button-animated {
      transition: none;
    }

    .button-animated::before {
      display: none;
    }

    .button-animated:hover {
      transform: none;
    }

    .ripple {
      animation: none;
      display: none;
    }
  }
</style>
