/**
 * POST /api/auth/register/verify
 *
 * Verify WebAuthn registration attestation and store the credential.
 * Receives the result of navigator.credentials.create() from the client.
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { RegistrationResponseJSON } from '@simplewebauthn/server';
import { env } from '$env/dynamic/private';

import { WebAuthnService, createWebAuthnConfig, getCredentialStore } from '$lib/server/auth';

interface VerifyRequestBody {
  credential: RegistrationResponseJSON;
  friendlyName?: string;
}

export const POST: RequestHandler = async ({ request }) => {
  try {
    const configResult = createWebAuthnConfig(env);

    if (!configResult.success) {
      return json(
        { error: configResult.error, code: configResult.code },
        { status: 503 }
      );
    }

    const store = getCredentialStore();
    const service = new WebAuthnService(configResult.config);

    // Parse request body
    const body = (await request.json()) as VerifyRequestBody;

    if (!body.credential) {
      return json(
        {
          error: 'Missing credential in request body',
          code: 'INVALID_REQUEST'
        },
        { status: 400 }
      );
    }

    // Get stored challenge
    const storedChallenge = await store.getChallenge();

    if (!storedChallenge) {
      return json(
        {
          error: 'No registration challenge found. Please start registration again.',
          code: 'NO_CHALLENGE'
        },
        { status: 400 }
      );
    }

    // Verify the registration response
    const credential = await service.verifyRegistration(
      body.credential,
      storedChallenge,
      body.friendlyName || 'Hardware Key'
    );

    // Store the verified credential
    await store.addCredential(credential);

    // Clear the used challenge
    await store.clearChallenge();

    return json({
      verified: true,
      credentialId: credential.id
    });
  } catch (error) {
    console.error('Registration verification error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    // Determine appropriate status code
    const status =
      message.includes('expired') || message.includes('Challenge')
        ? 400
        : message.includes('failed')
          ? 400
          : 500;

    return json(
      {
        error: message,
        code: 'VERIFICATION_FAILED'
      },
      { status }
    );
  }
};
