/**
 * Authentication configuration
 */

export type AuthMode = 'on' | 'off';

/**
 * Get the authentication mode from environment variables.
 * Default: 'off' (auth bypassed for local dev convenience)
 */
export function getAuthMode(env: Record<string, string | undefined>): AuthMode {
  const mode = env.AUTH_MODE;
  if (mode === 'on') return 'on';
  return 'off';
}

/**
 * Check if authentication is enabled.
 */
export function isAuthEnabled(env: Record<string, string | undefined>): boolean {
  return getAuthMode(env) === 'on';
}
