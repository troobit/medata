/**
 * credentialStoreFactory - Factory for credential store implementations
 *
 * Selects the appropriate credential store based on environment:
 * - KVCredentialStore when Vercel KV is configured (KV_REST_API_URL)
 * - FileCredentialStore for local development
 */

import type { ICredentialStore } from './ICredentialStore';
import { FileCredentialStore } from './FileCredentialStore';
import { KVCredentialStore } from './KVCredentialStore';

const DEFAULT_CREDENTIALS_PATH = './data/credentials.json';

let storeInstance: ICredentialStore | null = null;
let storeType: 'kv' | 'file' | null = null;

/**
 * Get the appropriate credential store for the current environment.
 * Returns KVCredentialStore when Vercel KV is configured, FileCredentialStore otherwise.
 * Caches the singleton instance for reuse.
 *
 * @param credentialsPath - Optional path for file-based storage (defaults to ./data/credentials.json)
 */
export function getCredentialStore(credentialsPath?: string): ICredentialStore {
  const isKVConfigured = !!process.env.KV_REST_API_URL;
  const expectedType = isKVConfigured ? 'kv' : 'file';

  // Return cached instance if type matches
  if (storeInstance && storeType === expectedType) {
    return storeInstance;
  }

  // Create new instance
  if (isKVConfigured) {
    storeInstance = new KVCredentialStore();
    storeType = 'kv';
  } else {
    const path = credentialsPath || DEFAULT_CREDENTIALS_PATH;
    storeInstance = new FileCredentialStore(path);
    storeType = 'file';
  }

  return storeInstance;
}

/**
 * Check if Vercel KV is configured for credential storage.
 */
export function isKVConfigured(): boolean {
  return !!process.env.KV_REST_API_URL;
}
