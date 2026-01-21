/**
 * PATCH/DELETE /api/auth/credentials/[id]
 *
 * Update or delete a specific credential (requires authentication).
 * DELETE prevents removal of the last credential to avoid lockout.
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

import { createWebAuthnConfig, getCredentialStore } from '$lib/server/auth';

interface UpdateCredentialRequest {
  friendlyName?: string;
}

/**
 * PATCH - Update credential metadata
 */
export const PATCH: RequestHandler = async ({ locals, params, request }) => {
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
    const { id } = params;

    if (!id) {
      return json(
        {
          error: 'Credential ID is required',
          code: 'INVALID_REQUEST'
        },
        { status: 400 }
      );
    }

    const config = createWebAuthnConfig(env);
    const store = getCredentialStore();

    // Check if credential exists
    const credential = await store.getCredentialById(id);

    if (!credential) {
      return json(
        {
          error: 'Credential not found',
          code: 'NOT_FOUND'
        },
        { status: 404 }
      );
    }

    // Parse request body
    const body = (await request.json()) as UpdateCredentialRequest;

    if (!body.friendlyName) {
      return json(
        {
          error: 'No updates provided',
          code: 'INVALID_REQUEST'
        },
        { status: 400 }
      );
    }

    // Update credential
    await store.updateCredential(id, {
      friendlyName: body.friendlyName
    });

    // Return updated credential info
    return json({
      id,
      friendlyName: body.friendlyName,
      createdAt: credential.createdAt,
      lastUsedAt: credential.lastUsedAt,
      deviceType: credential.deviceType,
      backedUp: credential.backedUp
    });
  } catch (error) {
    console.error('Update credential error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    return json(
      {
        error: message,
        code: 'UPDATE_CREDENTIAL_FAILED'
      },
      { status: 500 }
    );
  }
};

/**
 * DELETE - Remove a credential
 * Prevents deletion of the last remaining credential to avoid lockout.
 */
export const DELETE: RequestHandler = async ({ locals, params }) => {
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
    const { id } = params;

    if (!id) {
      return json(
        {
          error: 'Credential ID is required',
          code: 'INVALID_REQUEST'
        },
        { status: 400 }
      );
    }

    const config = createWebAuthnConfig(env);
    const store = getCredentialStore();

    // Check if credential exists
    const credential = await store.getCredentialById(id);

    if (!credential) {
      return json(
        {
          error: 'Credential not found',
          code: 'NOT_FOUND'
        },
        { status: 404 }
      );
    }

    // Check credential count - prevent deletion of last credential
    const count = await store.getCredentialCount();

    if (count <= 1) {
      return json(
        {
          error:
            'Cannot delete the last credential. Add another credential first to avoid lockout.',
          code: 'LOCKOUT_PREVENTION'
        },
        { status: 400 }
      );
    }

    // Remove credential
    await store.removeCredential(id);

    return json({ success: true });
  } catch (error) {
    console.error('Delete credential error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    return json(
      {
        error: message,
        code: 'DELETE_CREDENTIAL_FAILED'
      },
      { status: 500 }
    );
  }
};
