/**
 * POST /api/auth/register/options
 *
 * Generate WebAuthn registration options with challenge.
 * Returns options that the client uses to call navigator.credentials.create()
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

import { WebAuthnService, createWebAuthnConfig, getCredentialStore } from '$lib/server/auth';

export const POST: RequestHandler = async () => {
  try {
    const config = createWebAuthnConfig(env);
    const store = getCredentialStore(config.credentialsPath);
    const service = new WebAuthnService(config);

    // Get existing credentials to exclude from registration
    const existingCredentials = await store.getCredentials();

    // Generate registration options
    const { options, challenge } = await service.generateRegistrationOptions(existingCredentials);

    // Store challenge for verification
    await store.setChallenge(challenge);

    return json(options);
  } catch (error) {
    console.error('Registration options error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    return json(
      {
        error: message,
        code: 'REGISTRATION_OPTIONS_FAILED'
      },
      { status: 500 }
    );
  }
};
