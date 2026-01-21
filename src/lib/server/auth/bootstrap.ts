/**
 * Bootstrap - First credential enrollment logic
 *
 * Handles the initial credential registration for a fresh deployment
 * where no credentials exist yet. Requires a bootstrap token for security.
 */

import type { CredentialStore } from './CredentialStore';

export interface BootstrapConfig {
  token: string;
}

export interface BootstrapState {
  bootstrapAvailable: boolean;
  credentialCount: number;
}

export class BootstrapService {
  private store: CredentialStore;
  private config: BootstrapConfig;

  constructor(store: CredentialStore, config: BootstrapConfig) {
    this.store = store;
    this.config = config;
  }

  /**
   * Check if bootstrap is available (no credentials exist)
   */
  async isBootstrapAvailable(): Promise<boolean> {
    const hasCredentials = await this.store.hasCredentials();
    return !hasCredentials;
  }

  /**
   * Get current bootstrap state
   */
  async getBootstrapState(): Promise<BootstrapState> {
    const credentialCount = await this.store.getCredentialCount();
    return {
      bootstrapAvailable: credentialCount === 0,
      credentialCount
    };
  }

  /**
   * Validate the provided bootstrap token
   */
  validateToken(providedToken: string): boolean {
    if (!this.config.token || this.config.token.length === 0) {
      return false;
    }

    // Timing-safe comparison to prevent timing attacks
    if (providedToken.length !== this.config.token.length) {
      return false;
    }

    let result = 0;
    for (let i = 0; i < providedToken.length; i++) {
      result |= providedToken.charCodeAt(i) ^ this.config.token.charCodeAt(i);
    }

    return result === 0;
  }

  /**
   * Verify bootstrap is allowed (no credentials exist and valid token)
   * @throws Error if bootstrap is not allowed
   */
  async verifyBootstrapAllowed(providedToken: string): Promise<void> {
    const isAvailable = await this.isBootstrapAvailable();

    if (!isAvailable) {
      throw new Error('Bootstrap is not available: credentials already exist');
    }

    if (!this.validateToken(providedToken)) {
      throw new Error('Invalid bootstrap token');
    }
  }
}

/**
 * Create bootstrap config from environment variables
 */
export function createBootstrapConfig(env: Record<string, string | undefined>): BootstrapConfig {
  const token = env.AUTH_BOOTSTRAP_TOKEN || '';

  return { token };
}
