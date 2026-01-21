<script lang="ts">
  import type { Snippet } from 'svelte';
  import { Spring, prefersReducedMotion } from 'svelte/motion';
  import { scale as scaleTransition } from 'svelte/transition';
  import { cubicOut } from 'svelte/easing';

  interface Props {
    variant?: 'primary' | 'secondary' | 'ghost';
    size?: 'sm' | 'md' | 'lg';
    animation?: 'none' | 'subtle' | 'full';
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
    animation = 'subtle',
    loading = false,
    disabled = false,
    href,
    type = 'button',
    class: className = '',
    onclick,
    children
  }: Props = $props();

  // Spring for press/release scale feedback
  const pressSpring = new Spring(1, { stiffness: 0.3, damping: 0.8 });

  // Ripple effect state with Spring-based animation
  let ripples = $state<Array<{ id: number; x: number; y: number; spring: Spring<number> }>>([]);
  let rippleId = 0;

  // Check if animations should be disabled
  const shouldAnimate = $derived(animation !== 'none' && !prefersReducedMotion.current);
  const isFullAnimation = $derived(animation === 'full' && !prefersReducedMotion.current);

  const baseClasses =
    'inline-flex items-center justify-center font-medium rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-gray-950 disabled:opacity-50 disabled:cursor-not-allowed relative overflow-hidden';

  const variantClasses = {
    primary:
      'btn-primary bg-brand-accent text-gray-950 hover:bg-brand-accent/90 focus:ring-brand-accent',
    secondary:
      'btn-secondary bg-gray-800 text-gray-100 hover:bg-gray-700 focus:ring-gray-600 border border-gray-700',
    ghost: 'btn-ghost text-gray-300 hover:bg-gray-800 hover:text-white focus:ring-gray-600'
  };

  const sizeClasses = {
    sm: 'text-sm px-3 py-1.5 min-h-[32px]',
    md: 'text-base px-4 py-2 min-h-[44px]',
    lg: 'text-lg px-6 py-3 min-h-[52px]'
  };

  // Add gap utility classes for button containers to accommodate motion
  const motionClasses = $derived({
    'shadow-hover': shouldAnimate,
    'shadow-hover-full': isFullAnimation
  });

  const classes = $derived(
    [baseClasses, variantClasses[variant], sizeClasses[size], className].join(' ')
  );

  function createRipple(event: MouseEvent) {
    if (!shouldAnimate) return;

    const button = event.currentTarget as HTMLElement;
    const rect = button.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;

    const id = rippleId++;
    const spring = new Spring(0, { stiffness: 0.15, damping: 0.9 });

    ripples = [...ripples, { id, x, y, spring }];

    // Animate the ripple scale
    spring.set(20);

    // Remove ripple after animation completes
    setTimeout(() => {
      ripples = ripples.filter((r) => r.id !== id);
    }, 600);
  }

  function handlePointerDown() {
    if (shouldAnimate) {
      pressSpring.set(0.97);
    }
  }

  function handlePointerUp() {
    if (shouldAnimate) {
      pressSpring.set(1);
    }
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
    class:shadow-hover={shouldAnimate}
    class:shadow-hover-full={isFullAnimation}
    role="button"
    tabindex="0"
    onkeydown={handleKeyDown}
    onpointerdown={(e) => {
      handlePointerDown();
      createRipple(e);
    }}
    onpointerup={handlePointerUp}
    onpointerleave={handlePointerUp}
    style:transform={shouldAnimate ? `scale(${pressSpring.current})` : undefined}
  >
    <span class="button-content" class:content-hover={isFullAnimation}>
      {#if loading}
        <span
          class="mr-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
        ></span>
      {/if}
      {@render children()}
    </span>
    {#each ripples as ripple (ripple.id)}
      <span
        class="ripple"
        class:ripple-primary={variant === 'primary'}
        style="left: {ripple.x}px; top: {ripple.y}px; transform: scale({ripple.spring
          .current}); opacity: {1 - ripple.spring.current / 20};"
        transition:scaleTransition={{ duration: 300, easing: cubicOut, start: 0 }}
      ></span>
    {/each}
  </a>
{:else}
  <button
    {type}
    class={classes}
    class:shadow-hover={shouldAnimate}
    class:shadow-hover-full={isFullAnimation}
    disabled={disabled || loading}
    onclick={(e) => onclick?.(e)}
    onpointerdown={(e) => {
      handlePointerDown();
      createRipple(e);
    }}
    onpointerup={handlePointerUp}
    onpointerleave={handlePointerUp}
    style:transform={shouldAnimate ? `scale(${pressSpring.current})` : undefined}
  >
    <span class="button-content" class:content-hover={isFullAnimation}>
      {#if loading}
        <span
          class="mr-2 inline-block h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent"
        ></span>
      {/if}
      {@render children()}
    </span>
    {#each ripples as ripple (ripple.id)}
      <span
        class="ripple"
        class:ripple-primary={variant === 'primary'}
        style="left: {ripple.x}px; top: {ripple.y}px; transform: scale({ripple.spring
          .current}); opacity: {1 - ripple.spring.current / 20};"
        transition:scaleTransition={{ duration: 300, easing: cubicOut, start: 0 }}
      ></span>
    {/each}
  </button>
{/if}

<style>
  /* Hover effects using box-shadow instead of scale to prevent collision */
  .shadow-hover {
    transition:
      box-shadow 0.2s cubic-bezier(0.33, 1, 0.68, 1),
      background-color 0.2s cubic-bezier(0.33, 1, 0.68, 1);
  }

  .shadow-hover:hover:not(:disabled) {
    box-shadow:
      0 4px 12px rgba(0, 0, 0, 0.15),
      0 2px 4px rgba(0, 0, 0, 0.1);
  }

  .shadow-hover-full:hover:not(:disabled) {
    box-shadow:
      0 8px 24px rgba(0, 0, 0, 0.2),
      0 4px 8px rgba(0, 0, 0, 0.15);
  }

  .button-content {
    position: relative;
    z-index: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: transform 0.2s cubic-bezier(0.33, 1, 0.68, 1);
  }

  /* Inner element transform for full animation mode */
  .content-hover {
    transform-origin: center;
  }

  .shadow-hover-full:hover .content-hover {
    transform: scale(1.02);
  }

  /* Shimmer effect on hover - using CSS transitions with easing */
  .shadow-hover-full::before {
    content: '';
    position: absolute;
    top: 0;
    left: -100%;
    width: 100%;
    height: 100%;
    background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.3), transparent);
    transition: left 0.4s cubic-bezier(0.33, 1, 0.68, 1);
    z-index: 0;
  }

  /* Adjust shimmer for secondary and ghost variants */
  .shadow-hover-full.btn-secondary::before,
  .shadow-hover-full.btn-ghost::before {
    background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.12), transparent);
  }

  .shadow-hover-full:hover::before {
    left: 100%;
  }

  /* Ripple effect - Spring-based scaling */
  .ripple {
    position: absolute;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.4);
    width: 20px;
    height: 20px;
    margin-left: -10px;
    margin-top: -10px;
    pointer-events: none;
    z-index: 0;
  }

  /* Adjust ripple for primary variant (dark text) */
  .ripple-primary {
    background: rgba(0, 0, 0, 0.15);
  }

  /* Reduced motion - respects prefersReducedMotion from svelte/motion */
  @media (prefers-reduced-motion: reduce) {
    .shadow-hover,
    .shadow-hover-full,
    .button-content {
      transition: none;
    }

    .shadow-hover-full::before {
      display: none;
    }

    .shadow-hover-full:hover .content-hover {
      transform: none;
    }

    .ripple {
      display: none;
    }
  }
</style>
