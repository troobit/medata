import { getServerAuthClient, ServerAuthClientError } from '$lib/services/auth';
import { startAuthentication } from '@simplewebauthn/browser';

export type AuthState = 'unknown' | 'checking' | 'authenticated' | 'unauthenticated';

/**
 * Reactive store for authentication state using Svelte 5 runes
 */
function createAuthStore() {
  let state = $state<AuthState>('unknown');
  let expiresAt = $state<string | null>(null);
  let error = $state<string | null>(null);
  let loading = $state(false);

  const client = getServerAuthClient();

  /**
   * Check current session status with the server.
   */
  async function checkSession(): Promise<boolean> {
    state = 'checking';
    error = null;

    try {
      const status = await client.getSessionStatus();
      if (status.authenticated) {
        state = 'authenticated';
        expiresAt = status.expiresAt;
        return true;
      } else {
        state = 'unauthenticated';
        expiresAt = null;
        return false;
      }
    } catch (e) {
      state = 'unauthenticated';
      expiresAt = null;
      error = e instanceof Error ? e.message : 'Failed to check session';
      return false;
    }
  }

  /**
   * Perform full login flow with YubiKey.
   * Gets authentication options from server, prompts for YubiKey, verifies with server.
   */
  async function login(): Promise<boolean> {
    loading = true;
    error = null;

    try {
      // Get authentication options from server
      const options = await client.getLoginOptions();

      // Prompt for YubiKey authentication via WebAuthn browser API
      const credential = await startAuthentication({
        optionsJSON: options
      });

      // Verify credential with server
      const result = await client.verifyLogin(credential);

      if (result.verified) {
        state = 'authenticated';
        expiresAt = result.expiresAt;
        return true;
      } else {
        state = 'unauthenticated';
        error = 'Authentication failed';
        return false;
      }
    } catch (e) {
      state = 'unauthenticated';
      if (e instanceof ServerAuthClientError) {
        error = e.message;
      } else if (e instanceof Error) {
        // Handle WebAuthn-specific errors
        if (e.name === 'NotAllowedError') {
          error = 'Authentication was cancelled or timed out';
        } else if (e.name === 'SecurityError') {
          error = 'Security error during authentication';
        } else {
          error = e.message;
        }
      } else {
        error = 'Authentication failed';
      }
      return false;
    } finally {
      loading = false;
    }
  }

  /**
   * Logout and clear session.
   */
  async function logout(): Promise<void> {
    loading = true;
    error = null;

    try {
      await client.logout();
      state = 'unauthenticated';
      expiresAt = null;
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to logout';
      throw e;
    } finally {
      loading = false;
    }
  }

  /**
   * Clear any error state.
   */
  function clearError(): void {
    error = null;
  }

  const isAuthenticated = $derived(state === 'authenticated');
  const isChecking = $derived(state === 'checking' || state === 'unknown');

  return {
    get state() {
      return state;
    },
    get expiresAt() {
      return expiresAt;
    },
    get error() {
      return error;
    },
    get loading() {
      return loading;
    },
    get isAuthenticated() {
      return isAuthenticated;
    },
    get isChecking() {
      return isChecking;
    },
    checkSession,
    login,
    logout,
    clearError
  };
}

export const authStore = createAuthStore();
