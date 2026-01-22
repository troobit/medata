import prettier from 'eslint-config-prettier';
import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import globals from 'globals';
import ts from 'typescript-eslint';

export default ts.config(
  js.configs.recommended,
  ...ts.configs.recommended,
  ...svelte.configs['flat/recommended'],
  prettier,
  ...svelte.configs['flat/prettier'],
  {
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node
      }
    }
  },
  {
    files: ['**/*.svelte'],
    languageOptions: {
      parserOptions: {
        parser: ts.parser
      }
    }
  },
  {
    // Svelte 5 runes files use .svelte.ts extension and need svelte parser
    files: ['**/*.svelte.ts', '**/*.svelte.js'],
    languageOptions: {
      parser: svelte.parser,
      parserOptions: {
        parser: ts.parser
      }
    }
  },
  {
    // Project-specific rule adjustments
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_'
        }
      ],
      // Disable strict navigation resolution for single-domain personal app with no base path
      'svelte/no-navigation-without-resolve': 'off',
      // Disable strict each-key requirement (useful for dynamic lists, but overkill for static ones)
      'svelte/require-each-key': 'warn',
      // Disable SvelteDate/SvelteMap requirement (standard Date/Map work fine for most cases)
      'svelte/prefer-svelte-reactivity': 'off'
    }
  },
  {
    ignores: ['build/', '.svelte-kit/', 'dist/', '.vercel/', 'node_modules/']
  }
);
