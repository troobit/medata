/**
 * ICredentialStore - Interface for credential storage implementations
 *
 * Defines the contract for credential stores that can be backed by
 * different storage mechanisms (file system, Vercel KV, etc.)
 */

import type { StoredCredential, StoredChallenge } from './types';

export interface ICredentialStore {
  // Credential operations
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

  // Challenge operations
  getChallenge(): Promise<StoredChallenge | undefined>;
  setChallenge(challenge: StoredChallenge): Promise<void>;
  clearChallenge(): Promise<void>;
}
