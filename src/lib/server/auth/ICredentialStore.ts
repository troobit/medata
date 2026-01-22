/**
 * ICredentialStore - Interface for credential storage backends
 *
 * Defines the contract for credential persistence implementations.
 * Implementations include FileCredentialStore (local dev) and KVCredentialStore (Vercel).
 */

import type { StoredCredential, StoredChallenge } from './types';

export interface ICredentialStore {
  // Credentials
  getCredentials(): Promise<StoredCredential[]>;
  getCredentialById(id: string): Promise<StoredCredential | undefined>;
  addCredential(credential: StoredCredential): Promise<void>;
  updateCredential(
    id: string,
    updates: Partial<Pick<StoredCredential, 'counter' | 'lastUsedAt' | 'friendlyName'>>
  ): Promise<void>;
  removeCredential(id: string): Promise<void>;
  hasCredentials(): Promise<boolean>;
  getCredentialCount(): Promise<number>;

  // Challenge
  getChallenge(): Promise<StoredChallenge | undefined>;
  setChallenge(challenge: StoredChallenge): Promise<void>;
  clearChallenge(): Promise<void>;
}
