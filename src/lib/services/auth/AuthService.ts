/**
 * WebAuthn Authentication Service
 * Task 24: FIDO/YubiKey authentication
 *
 * Provides passwordless authentication using hardware security keys
 * and passkeys via the WebAuthn API.
 */

import type { User, StoredCredential, AuthSession, AuthConfig } from '$lib/types/auth';
import {
  DEFAULT_AUTH_CONFIG,
  AuthError,
  isWebAuthnSupported,
  arrayBufferToBase64,
  base64ToArrayBuffer,
  generateChallenge
} from '$lib/types/auth';

const STORAGE_KEYS = {
  USERS: 'medata_users',
  CREDENTIALS: 'medata_credentials',
  SESSION: 'medata_session',
  CONFIG: 'medata_auth_config'
};

export class AuthService {
  private config: AuthConfig;

  constructor(config?: Partial<AuthConfig>) {
    this.config = { ...DEFAULT_AUTH_CONFIG, ...config };
  }

  /**
   * Check if authentication is enabled and supported
   */
  isAvailable(): boolean {
    return this.config.enabled && isWebAuthnSupported();
  }

  /**
   * Get current configuration
   */
  getConfig(): AuthConfig {
    return { ...this.config };
  }

  /**
   * Update configuration
   */
  setConfig(config: Partial<AuthConfig>): void {
    this.config = { ...this.config, ...config };
    this.saveConfig();
  }

  /**
   * Register a new user with WebAuthn credential
   */
  async registerUser(username: string, displayName: string): Promise<User> {
    if (!isWebAuthnSupported()) {
      throw new AuthError('NOT_SUPPORTED', 'WebAuthn is not supported in this browser');
    }

    // Generate user ID
    const userId = crypto.randomUUID();
    const userIdBuffer = new TextEncoder().encode(userId);

    // Create registration options
    const challenge = generateChallenge();

    const options: PublicKeyCredentialCreationOptions = {
      challenge,
      rp: {
        name: this.config.rpName,
        id: this.config.rpId || window.location.hostname
      },
      user: {
        id: userIdBuffer,
        name: username,
        displayName
      },
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 }, // ES256
        { type: 'public-key', alg: -257 } // RS256
      ],
      timeout: this.config.timeout,
      attestation: 'none',
      authenticatorSelection: {
        authenticatorAttachment: this.config.authenticatorAttachment,
        userVerification: this.config.userVerification,
        residentKey: this.config.residentKey
      }
    };

    try {
      const credential = (await navigator.credentials.create({
        publicKey: options
      })) as PublicKeyCredential;

      if (!credential) {
        throw new AuthError('NOT_ALLOWED', 'User cancelled registration');
      }

      const response = credential.response as AuthenticatorAttestationResponse;

      // Extract public key from attestation
      const publicKeyBytes = response.getPublicKey?.();
      if (!publicKeyBytes) {
        throw new AuthError('UNKNOWN_ERROR', 'Failed to extract public key');
      }

      // Create user
      const user: User = {
        id: userId,
        username,
        displayName,
        createdAt: new Date()
      };

      // Store credential
      const storedCredential: StoredCredential = {
        credentialId: arrayBufferToBase64(credential.rawId),
        userId,
        publicKey: arrayBufferToBase64(publicKeyBytes),
        counter: 0,
        deviceType:
          this.config.authenticatorAttachment === 'platform' ? 'platform' : 'cross-platform',
        createdAt: new Date(),
        friendlyName: 'Security Key'
      };

      // Save to storage
      this.saveUser(user);
      this.saveCredential(storedCredential);

      // Create session
      this.createSession(user, storedCredential.credentialId);

      return user;
    } catch (error) {
      if (error instanceof AuthError) throw error;
      if (error instanceof DOMException) {
        switch (error.name) {
          case 'NotAllowedError':
            throw new AuthError('NOT_ALLOWED', 'User denied the registration request');
          case 'InvalidStateError':
            throw new AuthError('INVALID_STATE', 'Authenticator is already registered');
          case 'NotSupportedError':
            throw new AuthError('NOT_SUPPORTED', 'No supported authenticator found');
          default:
            throw new AuthError('UNKNOWN_ERROR', error.message);
        }
      }
      throw new AuthError('UNKNOWN_ERROR', 'Registration failed');
    }
  }

  /**
   * Add additional credential to existing user
   */
  async addCredential(userId: string, friendlyName?: string): Promise<StoredCredential> {
    const user = this.getUser(userId);
    if (!user) {
      throw new AuthError('INVALID_CREDENTIAL', 'User not found');
    }

    const existingCredentials = this.getUserCredentials(userId);
    const challenge = generateChallenge();

    const options: PublicKeyCredentialCreationOptions = {
      challenge,
      rp: {
        name: this.config.rpName,
        id: this.config.rpId || window.location.hostname
      },
      user: {
        id: new TextEncoder().encode(userId),
        name: user.username,
        displayName: user.displayName
      },
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 },
        { type: 'public-key', alg: -257 }
      ],
      timeout: this.config.timeout,
      attestation: 'none',
      excludeCredentials: existingCredentials.map((c) => ({
        type: 'public-key' as const,
        id: base64ToArrayBuffer(c.credentialId)
      })),
      authenticatorSelection: {
        authenticatorAttachment: this.config.authenticatorAttachment,
        userVerification: this.config.userVerification,
        residentKey: this.config.residentKey
      }
    };

    const credential = (await navigator.credentials.create({
      publicKey: options
    })) as PublicKeyCredential;

    if (!credential) {
      throw new AuthError('NOT_ALLOWED', 'User cancelled registration');
    }

    const response = credential.response as AuthenticatorAttestationResponse;
    const publicKeyBytes = response.getPublicKey?.();

    if (!publicKeyBytes) {
      throw new AuthError('UNKNOWN_ERROR', 'Failed to extract public key');
    }

    const storedCredential: StoredCredential = {
      credentialId: arrayBufferToBase64(credential.rawId),
      userId,
      publicKey: arrayBufferToBase64(publicKeyBytes),
      counter: 0,
      deviceType:
        this.config.authenticatorAttachment === 'platform' ? 'platform' : 'cross-platform',
      createdAt: new Date(),
      friendlyName: friendlyName || `Security Key ${existingCredentials.length + 1}`
    };

    this.saveCredential(storedCredential);

    return storedCredential;
  }

  /**
   * Authenticate user with WebAuthn
   */
  async authenticate(username?: string): Promise<AuthSession> {
    if (!isWebAuthnSupported()) {
      throw new AuthError('NOT_SUPPORTED', 'WebAuthn is not supported in this browser');
    }

    const challenge = generateChallenge();

    // Get allowed credentials
    let allowCredentials: PublicKeyCredentialDescriptor[] | undefined;

    if (username) {
      const user = this.getUserByUsername(username);
      if (!user) {
        throw new AuthError('INVALID_CREDENTIAL', 'User not found');
      }

      const credentials = this.getUserCredentials(user.id);
      if (credentials.length === 0) {
        throw new AuthError('INVALID_CREDENTIAL', 'No credentials registered for user');
      }

      allowCredentials = credentials.map((c) => ({
        type: 'public-key' as const,
        id: base64ToArrayBuffer(c.credentialId)
      }));
    }

    const options: PublicKeyCredentialRequestOptions = {
      challenge,
      timeout: this.config.timeout,
      rpId: this.config.rpId || window.location.hostname,
      allowCredentials,
      userVerification: this.config.userVerification
    };

    try {
      const credential = (await navigator.credentials.get({
        publicKey: options
      })) as PublicKeyCredential;

      if (!credential) {
        throw new AuthError('NOT_ALLOWED', 'User cancelled authentication');
      }

      // Find the credential
      const credentialId = arrayBufferToBase64(credential.rawId);
      const storedCredential = this.getCredential(credentialId);

      if (!storedCredential) {
        throw new AuthError('INVALID_CREDENTIAL', 'Credential not found');
      }

      // Get user
      const user = this.getUser(storedCredential.userId);
      if (!user) {
        throw new AuthError('INVALID_CREDENTIAL', 'User not found');
      }

      // Update credential last used
      storedCredential.lastUsedAt = new Date();
      this.saveCredential(storedCredential);

      // Update user last login
      user.lastLoginAt = new Date();
      this.saveUser(user);

      // Create session
      return this.createSession(user, credentialId);
    } catch (error) {
      if (error instanceof AuthError) throw error;
      if (error instanceof DOMException) {
        switch (error.name) {
          case 'NotAllowedError':
            throw new AuthError('NOT_ALLOWED', 'User denied the authentication request');
          case 'AbortError':
            throw new AuthError('TIMEOUT', 'Authentication timed out');
          default:
            throw new AuthError('UNKNOWN_ERROR', error.message);
        }
      }
      throw new AuthError('UNKNOWN_ERROR', 'Authentication failed');
    }
  }

  /**
   * Get current session
   */
  getCurrentSession(): AuthSession | null {
    const sessionData = localStorage.getItem(STORAGE_KEYS.SESSION);
    if (!sessionData) return null;

    const session: AuthSession = JSON.parse(sessionData);
    session.expiresAt = new Date(session.expiresAt);

    if (session.expiresAt < new Date()) {
      this.logout();
      return null;
    }

    return session;
  }

  /**
   * Logout current user
   */
  logout(): void {
    localStorage.removeItem(STORAGE_KEYS.SESSION);
  }

  /**
   * Get all registered users
   */
  getUsers(): User[] {
    const data = localStorage.getItem(STORAGE_KEYS.USERS);
    if (!data) return [];
    const users: User[] = JSON.parse(data);
    return users.map((u) => ({
      ...u,
      createdAt: new Date(u.createdAt),
      lastLoginAt: u.lastLoginAt ? new Date(u.lastLoginAt) : undefined
    }));
  }

  /**
   * Get user by ID
   */
  getUser(userId: string): User | null {
    const users = this.getUsers();
    return users.find((u) => u.id === userId) || null;
  }

  /**
   * Get user by username
   */
  getUserByUsername(username: string): User | null {
    const users = this.getUsers();
    return users.find((u) => u.username.toLowerCase() === username.toLowerCase()) || null;
  }

  /**
   * Delete user and their credentials
   */
  deleteUser(userId: string): void {
    // Remove credentials
    const credentials = this.getAllCredentials().filter((c) => c.userId !== userId);
    localStorage.setItem(STORAGE_KEYS.CREDENTIALS, JSON.stringify(credentials));

    // Remove user
    const users = this.getUsers().filter((u) => u.id !== userId);
    localStorage.setItem(STORAGE_KEYS.USERS, JSON.stringify(users));

    // Logout if this user was logged in
    const session = this.getCurrentSession();
    if (session?.userId === userId) {
      this.logout();
    }
  }

  /**
   * Get credentials for a user
   */
  getUserCredentials(userId: string): StoredCredential[] {
    return this.getAllCredentials().filter((c) => c.userId === userId);
  }

  /**
   * Delete a credential
   */
  deleteCredential(credentialId: string): void {
    const credentials = this.getAllCredentials().filter((c) => c.credentialId !== credentialId);
    localStorage.setItem(STORAGE_KEYS.CREDENTIALS, JSON.stringify(credentials));
  }

  // Private methods

  private createSession(user: User, credentialId?: string): AuthSession {
    const session: AuthSession = {
      userId: user.id,
      username: user.username,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days
      credentialId
    };

    localStorage.setItem(STORAGE_KEYS.SESSION, JSON.stringify(session));
    return session;
  }

  private saveUser(user: User): void {
    const users = this.getUsers().filter((u) => u.id !== user.id);
    users.push(user);
    localStorage.setItem(STORAGE_KEYS.USERS, JSON.stringify(users));
  }

  private saveCredential(credential: StoredCredential): void {
    const credentials = this.getAllCredentials().filter(
      (c) => c.credentialId !== credential.credentialId
    );
    credentials.push(credential);
    localStorage.setItem(STORAGE_KEYS.CREDENTIALS, JSON.stringify(credentials));
  }

  private getAllCredentials(): StoredCredential[] {
    const data = localStorage.getItem(STORAGE_KEYS.CREDENTIALS);
    if (!data) return [];
    const credentials: StoredCredential[] = JSON.parse(data);
    return credentials.map((c) => ({
      ...c,
      createdAt: new Date(c.createdAt),
      lastUsedAt: c.lastUsedAt ? new Date(c.lastUsedAt) : undefined
    }));
  }

  private getCredential(credentialId: string): StoredCredential | null {
    const credentials = this.getAllCredentials();
    return credentials.find((c) => c.credentialId === credentialId) || null;
  }

  private saveConfig(): void {
    localStorage.setItem(STORAGE_KEYS.CONFIG, JSON.stringify(this.config));
  }
}

// Singleton instance
let authServiceInstance: AuthService | null = null;

export function getAuthService(): AuthService {
  if (!authServiceInstance) {
    // Load config from storage
    const storedConfig = localStorage.getItem(STORAGE_KEYS.CONFIG);
    const config = storedConfig ? JSON.parse(storedConfig) : undefined;
    authServiceInstance = new AuthService(config);
  }
  return authServiceInstance;
}
