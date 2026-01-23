import adapterVercel from '@sveltejs/adapter-vercel';
import adapterNode from '@sveltejs/adapter-node';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

const adapterProvider = process.env.ADAPTER_PROVIDER || 'vercel';

function getAdapter() {
  if (adapterProvider === 'node') {
    return adapterNode();
  }
  return adapterVercel({ runtime: 'nodejs22.x' });
}

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  compilerOptions: {
    // Suppress warnings for intentional patterns:
    // - state_referenced_locally: Used for editable copies of props that sync via $effect
    // - non_reactive_update: Used for DOM element bindings (bind:this)
    warningFilter: (warning) => {
      const suppressedCodes = [
        'state_referenced_locally', // Used for editable copies of props that sync via $effect
        'non_reactive_update', // Used for DOM element bindings (bind:this)
        'a11y_no_noninteractive_tabindex' // False positive when element has role="application"
      ];
      return !suppressedCodes.includes(warning.code);
    }
  },
  kit: {
    adapter: getAdapter(),
    alias: {
      $lib: './src/lib'
    },
    prerender: {
      // These redirect routes are prerenderable but not discovered via crawling
      // since they redirect to other files and aren't linked from any page
      entries: ['*', '/favicon.ico', '/apple-touch-icon.png'],
      handleUnseenRoutes: 'ignore'
    }
  }
};

export default config;
