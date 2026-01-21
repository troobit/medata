/**
 * KVCredentialStore - Vercel KV-based credential persistence
 *
 * Stores credentials in Vercel KV for serverless deployments.
 * Challenges use TTL for automatic expiry.
 */

import { kv } from '@vercel/kv';

import type { ICredentialStore } from './ICredentialStore';
import type { StoredCredential, StoredChallenge } from './types';

const CREDENTIALS_KEY = 'credentials';
const CHALLENGE_KEY = 'challenge';
const CHALLENGE_TTL_SECONDS = 300; // 5 minutes

export class KVCredentialStore implements ICredentialStore {
  /**
   * Get all stored credentials
   */
  async getCredentials(): Promise<StoredCredential[]> {
    const credentials = await kv.get<StoredCredential[]>(CREDENTIALS_KEY);
    return credentials ?? [];
  }

  /**
   * Get a credential by ID
   */
  async getCredentialById(id: string): Promise<StoredCredential | undefined> {
    const credentials = await this.getCredentials();
    return credentials.find((c) => c.id === id);
  }

  /**
   * Add a new credential
   */
  async addCredential(credential: StoredCredential): Promise<void> {
    const credentials = await this.getCredentials();

    // Check for duplicate
    if (credentials.some((c) => c.id === credential.id)) {
      throw new Error('Credential already exists');
    }

    credentials.push(credential);
    await kv.set(CREDENTIALS_KEY, credentials);
  }

  /**
   * Update a credential (e.g., update counter, lastUsedAt)
   */
  async updateCredential(
    id: string,
    updates: Partial<Pick<StoredCredential, 'counter' | 'lastUsedAt' | 'friendlyName'>>
  ): Promise<void> {
    const credentials = await this.getCredentials();
    const index = credentials.findIndex((c) => c.id === id);

    if (index === -1) {
      throw new Error('Credential not found');
    }

    credentials[index] = {
      ...credentials[index],
      ...updates
    };

    await kv.set(CREDENTIALS_KEY, credentials);
  }

  /**
   * Remove a credential by ID
   */
  async removeCredential(id: string): Promise<void> {
    const credentials = await this.getCredentials();
    const index = credentials.findIndex((c) => c.id === id);

    if (index === -1) {
      throw new Error('Credential not found');
    }

    credentials.splice(index, 1);
    await kv.set(CREDENTIALS_KEY, credentials);
  }

  /**
   * Check if any credentials exist
   */
  async hasCredentials(): Promise<boolean> {
    const credentials = await this.getCredentials();
    return credentials.length > 0;
  }

  /**
   * Get credential count
   */
  async getCredentialCount(): Promise<number> {
    const credentials = await this.getCredentials();
    return credentials.length;
  }

  /**
   * Get the current challenge (for verification)
   * Returns undefined if challenge doesn't exist or is expired
   */
  async getChallenge(): Promise<StoredChallenge | undefined> {
    const challenge = await kv.get<StoredChallenge>(CHALLENGE_KEY);
    if (!challenge) {
      return undefined;
    }

    // Check if expired (KV TTL should handle this, but double-check)
    if (Date.now() > challenge.expiresAt) {
      await this.clearChallenge();
      return undefined;
    }

    return challenge;
  }

  /**
   * Store a challenge with TTL
   */
  async setChallenge(challenge: StoredChallenge): Promise<void> {
    await kv.set(CHALLENGE_KEY, challenge, { ex: CHALLENGE_TTL_SECONDS });
  }

  /**
   * Clear the current challenge
   */
  async clearChallenge(): Promise<void> {
    await kv.del(CHALLENGE_KEY);
  }
}

/**
 * Singleton instance
 */
let storeInstance: KVCredentialStore | null = null;

export function getKVCredentialStore(): KVCredentialStore {
  if (!storeInstance) {
    storeInstance = new KVCredentialStore();
  }
  return storeInstance;
}
