/**
 * Client-side API wrapper for server authentication endpoints.
 * Handles WebAuthn credential interactions and session management.
 */

import type {
  AuthenticationOptionsResponse,
  SessionStatusResponse,
  AuthErrorResponse
} from '$lib/server/auth/types';
import type { AuthenticationResponseJSON } from '@simplewebauthn/browser';

export interface LoginVerifyResponse {
  verified: boolean;
  expiresAt: string;
}

export interface LogoutResponse {
  success: boolean;
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
