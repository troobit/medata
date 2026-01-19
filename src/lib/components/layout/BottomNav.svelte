<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';

  interface NavItem {
    href: string;
    label: string;
    icon: string;
  }

  const navItems: NavItem[] = [
    { href: '/', label: 'Home', icon: 'home' },
    { href: '/log', label: 'Log', icon: 'plus-circle' },
    { href: '/history', label: 'History', icon: 'list' },
    { href: '/settings', label: 'Settings', icon: 'settings' }
  ];

  function isActive(href: string, pathname: string): boolean {
    if (href === '/') {
      return pathname === '/';
    }
    return pathname.startsWith(href);
  }

  function getActiveIndex(pathname: string): number {
    return navItems.findIndex((item) => isActive(item.href, pathname));
  }

  let activeIndex = $derived(getActiveIndex($page.url.pathname));
  let navContainer: HTMLElement;
  let underlineStyle = $state({ left: '0px', width: '0px' });

  // Update underline position when active item changes
  $effect(() => {
    if (navContainer && activeIndex >= 0) {
      const items = navContainer.querySelectorAll('a');
      const activeItem = items[activeIndex] as HTMLElement;
      if (activeItem) {
        underlineStyle = {
          left: `${activeItem.offsetLeft}px`,
          width: `${activeItem.offsetWidth}px`
        };
      }
    }
  });

  onMount(() => {
    // Initial position
    if (navContainer && activeIndex >= 0) {
      const items = navContainer.querySelectorAll('a');
      const activeItem = items[activeIndex] as HTMLElement;
      if (activeItem) {
        underlineStyle = {
          left: `${activeItem.offsetLeft}px`,
          width: `${activeItem.offsetWidth}px`
        };
      }
    }
  });
</script>

<nav
  class="fixed bottom-0 left-0 right-0 z-50 border-t border-gray-800 bg-gray-950/95 backdrop-blur-sm pb-safe"
>
  <div class="relative mx-auto flex max-w-lg items-center justify-around" bind:this={navContainer}>
    <!-- Sliding underline indicator -->
    <div
      class="absolute top-0 h-[2px] bg-gradient-to-r from-brand-accent to-brand-accent/70 transition-all duration-300 ease-out"
      style="left: {underlineStyle.left}; width: {underlineStyle.width};"
    ></div>

    {#each navItems as item (item.href)}
      {@const active = isActive(item.href, $page.url.pathname)}
      <a
        href={item.href}
        class="flex min-h-[56px] min-w-[64px] flex-col items-center justify-center px-3 py-2 transition-colors duration-200 {active
          ? 'text-brand-accent'
          : 'text-gray-400 hover:text-gray-200'}"
        aria-current={active ? 'page' : undefined}
      >
        <svg
          class="h-6 w-6 transition-transform duration-200 {active ? 'scale-110' : ''}"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          {#if item.icon === 'home'}
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
            />
          {:else if item.icon === 'plus-circle'}
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v3m0 0v3m0-3h3m-3 0H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          {:else if item.icon === 'list'}
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 6h16M4 10h16M4 14h16M4 18h16"
            />
          {:else if item.icon === 'settings'}
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
            />
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
            />
          {/if}
        </svg>
        <span class="mt-1 text-xs">{item.label}</span>
      </a>
    {/each}
  </div>
</nav>
