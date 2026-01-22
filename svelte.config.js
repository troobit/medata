import adapter from '@sveltejs/adapter-vercel';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

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
    adapter: adapter({
      runtime: 'nodejs22.x'
    }),
    alias: {
      $lib: './src/lib'
    }
  }
};

export default config;
