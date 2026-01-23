/**
 * Credential Store Factory
 *
 * Environment-aware factory that returns the appropriate credential store:
 * - KVCredentialStore when Vercel KV is configured (KV_REST_API_URL env var)
 * - FileCredentialStore for local development
 *
 * On Vercel deployments (detected via VERCEL env var), KV is required since
 * the filesystem is read-only. An error is thrown if KV is not configured.
 */

import type { ICredentialStore } from './ICredentialStore';
import { FileCredentialStore } from './FileCredentialStore';
import { KVCredentialStore } from './KVCredentialStore';

const DEFAULT_CREDENTIALS_PATH = './data/credentials.json';

let cachedStore: ICredentialStore | null = null;

/**
 * Check if running on Vercel (serverless environment with read-only filesystem)
 */
function isVercelEnvironment(): boolean {
  return !!process.env.VERCEL;
}

/**
 * Get the appropriate credential store based on environment.
 *
 * Uses Vercel KV when KV_REST_API_URL is set, otherwise falls back
 * to file-based storage for local development.
 *
 * @param credentialsPath - Optional path for file-based store (defaults to ./data/credentials.json)
 * @returns Singleton instance of the appropriate credential store
 * @throws Error if running on Vercel without KV configured
 */
export function getCredentialStore(credentialsPath?: string): ICredentialStore {
  if (cachedStore) {
    return cachedStore;
  }

  // Check for Vercel KV configuration
  if (process.env.KV_REST_API_URL) {
    cachedStore = new KVCredentialStore();
  } else if (isVercelEnvironment()) {
    // On Vercel without KV - throw a helpful error
    throw new Error(
      'Vercel KV is not configured. ' +
        'File-based storage is not available on Vercel due to read-only filesystem. ' +
        'Please configure Vercel KV: https://vercel.com/docs/storage/vercel-kv/quickstart ' +
        'Then link it to your project: vercel link && vercel env pull'
    );
  } else {
    // Fall back to file-based storage for local development
    const path = credentialsPath ?? process.env.AUTH_CREDENTIALS_PATH ?? DEFAULT_CREDENTIALS_PATH;
    cachedStore = new FileCredentialStore(path);
  }

  return cachedStore;
}

/**
 * Check if KV-based storage is available.
 * Useful for logging/debugging which storage backend is active.
 */
export function isKVStorageAvailable(): boolean {
  return !!process.env.KV_REST_API_URL;
}

/**
 * Clear the cached store instance.
 * Primarily for testing purposes.
 */
export function clearCredentialStoreCache(): void {
  cachedStore = null;
}
