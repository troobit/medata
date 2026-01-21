/**
 * Client-side API wrapper for server authentication endpoints.
 * Handles WebAuthn credential interactions and session management.
 */

import type {
  AuthenticationOptionsResponse,
  RegistrationOptionsResponse,
  SessionStatusResponse,
  AuthErrorResponse
} from '$lib/server/auth/types';
import type { AuthenticationResponseJSON, RegistrationResponseJSON } from '@simplewebauthn/browser';

export interface LoginVerifyResponse {
  verified: boolean;
  expiresAt: string;
}

export interface LogoutResponse {
  success: boolean;
}

export interface CredentialInfo {
  id: string;
  friendlyName: string;
  createdAt: string;
  lastUsedAt: string | null;
  deviceType: string;
  backedUp: boolean;
}

export interface CredentialsListResponse {
  credentials: CredentialInfo[];
}

export interface RegistrationVerifyResponse {
  verified: boolean;
  credentialId: string;
}

export class ServerAuthClientError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly status: number
  ) {
    super(message);
    this.name = 'ServerAuthClientError';
  }
}

/**
 * Client for interacting with the server-side authentication API.
 */
export class ServerAuthClient {
  /**
   * Check current session status.
   * @returns Session status including authentication state and expiry
   */
  async getSessionStatus(): Promise<SessionStatusResponse> {
    const response = await fetch('/api/auth/session', {
      method: 'GET',
      credentials: 'include'
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<SessionStatusResponse>;
  }

  /**
   * Get authentication options from server.
   * This returns the challenge and allowed credentials for WebAuthn authentication.
   * @returns Authentication options to pass to navigator.credentials.get()
   */
  async getLoginOptions(): Promise<AuthenticationOptionsResponse> {
    const response = await fetch('/api/auth/login/options', {
      method: 'POST',
      credentials: 'include'
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<AuthenticationOptionsResponse>;
  }

  /**
   * Verify the authentication response and create a session.
   * @param credential - The credential response from navigator.credentials.get()
   * @returns Verification result with session expiry
   */
  async verifyLogin(credential: AuthenticationResponseJSON): Promise<LoginVerifyResponse> {
    const response = await fetch('/api/auth/login/verify', {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ credential })
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<LoginVerifyResponse>;
  }

  /**
   * Logout and clear the session.
   * @returns Logout result
   */
  async logout(): Promise<LogoutResponse> {
    const response = await fetch('/api/auth/logout', {
      method: 'POST',
      credentials: 'include'
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<LogoutResponse>;
  }

  /**
   * List all registered credentials.
   * @returns List of credential info
   */
  async listCredentials(): Promise<CredentialsListResponse> {
    const response = await fetch('/api/auth/credentials', {
      method: 'GET',
      credentials: 'include'
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<CredentialsListResponse>;
  }

  /**
   * Update a credential's metadata.
   * @param id - Credential ID
   * @param friendlyName - New friendly name
   * @returns Updated credential info
   */
  async updateCredential(id: string, friendlyName: string): Promise<CredentialInfo> {
    const response = await fetch(`/api/auth/credentials/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ friendlyName })
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<CredentialInfo>;
  }

  /**
   * Delete a credential.
   * @param id - Credential ID
   */
  async deleteCredential(id: string): Promise<void> {
    const response = await fetch(`/api/auth/credentials/${encodeURIComponent(id)}`, {
      method: 'DELETE',
      credentials: 'include'
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }
  }

  /**
   * Get registration options for adding a new credential (authenticated).
   * @returns Registration options to pass to navigator.credentials.create()
   */
  async getRegistrationOptions(): Promise<RegistrationOptionsResponse> {
    const response = await fetch('/api/auth/register/options', {
      method: 'POST',
      credentials: 'include'
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<RegistrationOptionsResponse>;
  }

  /**
   * Verify and add a new credential (authenticated).
   * @param credential - The credential response from navigator.credentials.create()
   * @param friendlyName - Friendly name for the credential
   * @returns Verification result
   */
  async verifyRegistration(
    credential: RegistrationResponseJSON,
    friendlyName?: string
  ): Promise<RegistrationVerifyResponse> {
    const response = await fetch('/api/auth/register/verify', {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ credential, friendlyName })
    });

    if (!response.ok) {
      const error = (await response.json()) as AuthErrorResponse;
      throw new ServerAuthClientError(error.error, error.code, response.status);
    }

    return response.json() as Promise<RegistrationVerifyResponse>;
  }
}

// Singleton instance
let authClient: ServerAuthClient | null = null;

/**
 * Get the singleton ServerAuthClient instance.
 */
export function getServerAuthClient(): ServerAuthClient {
  if (!authClient) {
    authClient = new ServerAuthClient();
  }
  return authClient;
}
