/**
 * CredentialStore - File-based credential persistence
 *
 * Stores credentials in a JSON file for single-user deployments.
 * For production on Vercel, consider using Vercel KV for persistence.
 */

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

import type { StoredCredential, StoredChallenge, CredentialStoreData } from './types';

export class CredentialStore {
  private filePath: string;
  private data: CredentialStoreData | null = null;

  constructor(filePath: string) {
    this.filePath = filePath;
  }

  /**
   * Load credentials from file
   */
  private async load(): Promise<CredentialStoreData> {
    if (this.data) {
      return this.data;
    }

    try {
      const content = await readFile(this.filePath, 'utf-8');
      this.data = JSON.parse(content) as CredentialStoreData;
      return this.data;
    } catch (error) {
      // File doesn't exist, return empty data
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        this.data = { credentials: [] };
        return this.data;
      }
      throw error;
    }
  }

  /**
   * Save credentials to file
   */
  private async save(): Promise<void> {
    if (!this.data) {
      return;
    }

    // Ensure directory exists
    const dir = dirname(this.filePath);
    await mkdir(dir, { recursive: true });

    await writeFile(this.filePath, JSON.stringify(this.data, null, 2), 'utf-8');
  }

  /**
   * Get all stored credentials
   */
  async getCredentials(): Promise<StoredCredential[]> {
    const data = await this.load();
    return data.credentials;
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
    const data = await this.load();

    // Check for duplicate
    if (data.credentials.some((c) => c.id === credential.id)) {
      throw new Error('Credential already exists');
    }

    data.credentials.push(credential);
    await this.save();
  }

  /**
   * Update a credential (e.g., update counter, lastUsedAt)
   */
  async updateCredential(
    id: string,
    updates: Partial<Pick<StoredCredential, 'counter' | 'lastUsedAt' | 'friendlyName'>>
  ): Promise<void> {
    const data = await this.load();
    const index = data.credentials.findIndex((c) => c.id === id);

    if (index === -1) {
      throw new Error('Credential not found');
    }

    data.credentials[index] = {
      ...data.credentials[index],
      ...updates
    };

    await this.save();
  }

  /**
   * Remove a credential by ID
   */
  async removeCredential(id: string): Promise<void> {
    const data = await this.load();
    const index = data.credentials.findIndex((c) => c.id === id);

    if (index === -1) {
      throw new Error('Credential not found');
    }

    data.credentials.splice(index, 1);
    await this.save();
  }

  /**
   * Get the current challenge (for verification)
   */
  async getChallenge(): Promise<StoredChallenge | undefined> {
    const data = await this.load();
    return data.currentChallenge;
  }

  /**
   * Store a challenge temporarily
   */
  async setChallenge(challenge: StoredChallenge): Promise<void> {
    const data = await this.load();
    data.currentChallenge = challenge;
    await this.save();
  }

  /**
   * Clear the current challenge
   */
  async clearChallenge(): Promise<void> {
    const data = await this.load();
    delete data.currentChallenge;
    await this.save();
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
}

/**
 * Singleton instance factory
 */
let storeInstance: CredentialStore | null = null;

export function getCredentialStore(filePath: string): CredentialStore {
  if (!storeInstance || storeInstance['filePath'] !== filePath) {
    storeInstance = new CredentialStore(filePath);
  }
  return storeInstance;
}
