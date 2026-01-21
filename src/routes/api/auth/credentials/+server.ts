/**
 * GET /api/auth/credentials
 *
 * List all registered credentials (requires authentication).
 * Returns credential info without sensitive data (publicKey).
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

import { getCredentialStore } from '$lib/server/auth';

export interface CredentialInfo {
  id: string;
  friendlyName: string;
  createdAt: string;
  lastUsedAt: string | null;
  deviceType: string;
  backedUp: boolean;
}

export const GET: RequestHandler = async ({ locals }) => {
  // Check authentication
  if (!locals.session) {
    return json(
      {
        error: 'Authentication required',
        code: 'UNauthoriseD'
      },
      { status: 401 }
    );
  }

  try {
    // Note: config available for future WebAuthn options if needed
    // const config = createWebAuthnConfig(env);
    const store = getCredentialStore();

    const credentials = await store.getCredentials();

    // Map to safe credential info (exclude publicKey and counter)
    const credentialInfos: CredentialInfo[] = credentials.map((cred) => ({
      id: cred.id,
      friendlyName: cred.friendlyName,
      createdAt: cred.createdAt,
      lastUsedAt: cred.lastUsedAt,
      deviceType: cred.deviceType,
      backedUp: cred.backedUp
    }));

    return json({ credentials: credentialInfos });
  } catch (error) {
    console.error('List credentials error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    return json(
      {
        error: message,
        code: 'LIST_CREDENTIALS_FAILED'
      },
      { status: 500 }
    );
  }
};
