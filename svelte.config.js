import adapter from '@sveltejs/adapter-vercel';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({ runtime: 'nodejs22.x' }),
    alias: {
      $lib: './src/lib'
    },
    prerender: {
      handleHttpError: ({ path, message }) => {
        // Ignore 404s for static assets during prerendering
        if (path === '/favicon.ico' || path === '/apple-touch-icon.png') {
          return;
        }
        throw new Error(message);
      }
    }
  }
};

export default config;
