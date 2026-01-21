<script lang="ts">
  import { env } from '$env/dynamic/public';

  type LogoVariant = 'default' | 'pride' | 'contrast';

  interface Props {
    size?: 'sm' | 'md' | 'lg' | 'splash';
    animated?: boolean;
    class?: string;
  }

  let { size = 'md', animated = false, class: className = '' }: Props = $props();

  const sizeMap: Record<Props['size'] & string, number> = {
    sm: 16,
    md: 32,
    lg: 48,
    splash: 96
  };

  const pixelSize = $derived(sizeMap[size]);

  // Pre-calculated path lengths for stroke-dasharray animation
  // Main path: bezier curve (~216) + vertical line (40) = ~256
  // Right vertical: 52 (from y=52 to y=104)
  // Center dot: 0.01 (minimal length, rendered as dot via stroke-linecap)
  const pathLengths = {
    main: 256,
    right: 52,
    dot: 0.01
  };

  // Validate variant from environment, fallback to default
  const validVariants: LogoVariant[] = ['default', 'pride', 'contrast'];
  const envVariant = env.PUBLIC_LOGO_VARIANT;
  const variant: LogoVariant = validVariants.includes(envVariant as LogoVariant)
    ? (envVariant as LogoVariant)
    : 'default';

  // Variant color schemes
  const variantColors = {
    default: { main: '#63ff00', dot: '#63ff00' },
    contrast: { main: '#000000', dot: '#ffcc00' },
    pride: { main: 'url(#pride-gradient)', dot: 'url(#pride-gradient)' }
  };

  const colors = variantColors[variant];
  const isPrideVariant = variant === 'pride';
</script>

<svg
  xmlns="http://www.w3.org/2000/svg"
  width={pixelSize}
  height={pixelSize}
  viewBox="0 0 128 128"
  role="img"
  aria-label="MeData logo"
  class="{className} {animated ? 'logo-animated' : ''}"
  style="--path-main: {pathLengths.main}; --path-right: {pathLengths.right}; --path-dot: {pathLengths.dot};"
>
  {#if isPrideVariant}
    <!-- Pride rainbow gradient definition -->
    <defs>
      <linearGradient id="pride-gradient" x1="0%" y1="0%" x2="100%" y2="0%">
        <stop offset="0%" stop-color="#E40303" />
        <stop offset="20%" stop-color="#FF8C00" />
        <stop offset="40%" stop-color="#FFED00" />
        <stop offset="60%" stop-color="#008026" />
        <stop offset="80%" stop-color="#24408E" />
        <stop offset="100%" stop-color="#732982" />
      </linearGradient>
    </defs>
  {/if}
  <!-- Main curve and left vertical -->
  <path
    class="logo-main"
    fill="none"
    stroke={colors.main}
    stroke-width="24"
    stroke-linecap="round"
    stroke-linejoin="round"
    d="M 24,24 C 130,24 130,104 24,104 L 24,64"
    style="stroke-dasharray: {pathLengths.main}; stroke-dashoffset: 0;"
  />
  <!-- Right vertical (starts at y=52 so round cap is hidden under curve) -->
  <path
    class="logo-right"
    fill="none"
    stroke={colors.main}
    stroke-width="24"
    stroke-linecap="round"
    stroke-linejoin="round"
    d="M 104,52 L 104,104"
    style="stroke-dasharray: {pathLengths.right}; stroke-dashoffset: 0;"
  />
  <!-- Center dot -->
  <path
    class="logo-dot"
    fill="none"
    stroke={colors.dot}
    stroke-width="24"
    stroke-linecap="round"
    stroke-linejoin="round"
    d="M 64,64 L 64,64"
    style="stroke-dasharray: {pathLengths.dot}; stroke-dashoffset: 0;"
  />
</svg>

<style>
  /* Main path animation: draws first (0-35%), stays (35-65%), undraws last (65-100%) */
  @keyframes stroke-main {
    0% {
      stroke-dashoffset: 256;
    }
    /* Draw complete */
    35%,
    65% {
      stroke-dashoffset: 0;
    }
    /* Undraw complete */
    100% {
      stroke-dashoffset: 256;
    }
  }

  /* Right vertical animation: draws second (15-42%), stays (42-58%), undraws second (58-85%) */
  @keyframes stroke-right {
    0%,
    15% {
      stroke-dashoffset: 52;
    }
    /* Draw complete */
    42%,
    58% {
      stroke-dashoffset: 0;
    }
    /* Undraw complete */
    85%,
    100% {
      stroke-dashoffset: 52;
    }
  }

  /* Center dot animation: draws last (30-50%), undraws first (50-70%) */
  @keyframes stroke-dot {
    0%,
    30% {
      stroke-dashoffset: 0.01;
    }
    /* Draw complete */
    50% {
      stroke-dashoffset: 0;
    }
    /* Undraw complete */
    70%,
    100% {
      stroke-dashoffset: 0.01;
    }
  }

  /* Animation duration and timing */
  :global(.logo-animated) .logo-main {
    animation: stroke-main 3s ease-in-out infinite;
    will-change: stroke-dashoffset;
  }

  :global(.logo-animated) .logo-right {
    animation: stroke-right 3s ease-in-out infinite;
    will-change: stroke-dashoffset;
  }

  :global(.logo-animated) .logo-dot {
    animation: stroke-dot 3s ease-in-out infinite;
    will-change: stroke-dashoffset;
  }
</style>
