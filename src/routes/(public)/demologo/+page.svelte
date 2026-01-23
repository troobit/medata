<script lang="ts">
  import { Logo } from '$lib/components/ui';
</script>

<div class="container mx-auto px-4 py-8">
  <h1 class="mb-8 text-3xl font-bold text-white">Logo Demo</h1>

  <!-- All sizes section -->
  <section class="mb-12">
    <h2 class="mb-6 text-xl font-semibold text-gray-200">All Sizes</h2>
    <div class="space-y-8">
      <!-- Small (16px) -->
      <div class="flex items-center gap-4">
        <div class="w-24 text-sm text-gray-400">sm (16px)</div>
        <div class="flex items-center gap-4">
          <Logo size="sm" />
          <Logo size="sm" animated />
          <span class="text-xs text-gray-500">(animated)</span>
        </div>
      </div>

      <!-- Medium (32px) -->
      <div class="flex items-center gap-4">
        <div class="w-24 text-sm text-gray-400">md (32px)</div>
        <div class="flex items-center gap-4">
          <Logo size="md" />
          <Logo size="md" animated />
          <span class="text-xs text-gray-500">(animated)</span>
        </div>
      </div>

      <!-- Large (48px) -->
      <div class="flex items-center gap-4">
        <div class="w-24 text-sm text-gray-400">lg (48px)</div>
        <div class="flex items-center gap-4">
          <Logo size="lg" />
          <Logo size="lg" animated />
          <span class="text-xs text-gray-500">(animated)</span>
        </div>
      </div>

      <!-- Splash (96px) -->
      <div class="flex items-center gap-4">
        <div class="w-24 text-sm text-gray-400">splash (96px)</div>
        <div class="flex items-center gap-4">
          <Logo size="splash" />
          <Logo size="splash" animated />
          <span class="text-xs text-gray-500">(animated)</span>
        </div>
      </div>
    </div>
  </section>

  <!-- Animation showcase -->
  <section class="mb-12">
    <h2 class="mb-6 text-xl font-semibold text-gray-200">Animation Showcase</h2>
    <div class="flex flex-wrap items-end gap-8">
      <Logo size="sm" animated />
      <Logo size="md" animated />
      <Logo size="lg" animated />
      <Logo size="splash" animated />
    </div>
  </section>

  <!-- Static comparison -->
  <section class="mb-12">
    <h2 class="mb-6 text-xl font-semibold text-gray-200">Static Comparison</h2>
    <div class="flex flex-wrap items-end gap-8">
      <Logo size="sm" />
      <Logo size="md" />
      <Logo size="lg" />
      <Logo size="splash" />
    </div>
  </section>

  <!-- Variant info -->
  <section>
    <h2 class="mb-4 text-xl font-semibold text-gray-200">Current Variant</h2>
    <p class="text-gray-400">
      The logo variant is controlled by the <code class="rounded bg-gray-800 px-2 py-1 text-sm"
        >PUBLIC_LOGO_VARIANT</code
      > environment variable at build time.
    </p>
    <p class="mt-2 text-gray-400">
      Available variants: <code class="text-sm text-green-400">default</code>,
      <code class="text-sm text-yellow-400">contrast</code>,
      <code class="text-sm text-pink-400">colour</code>
    </p>
  </section>
</div>
