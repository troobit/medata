/**
 * POST /api/auth/login/options
 *
 * Generate WebAuthn authentication options with challenge.
 * Returns options that the client uses to call navigator.credentials.get()
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

import { WebAuthnService, createWebAuthnConfig, getCredentialStore } from '$lib/server/auth';

export const POST: RequestHandler = async () => {
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

    // Get registered credentials
    const credentials = await store.getCredentials();

    if (credentials.length === 0) {
      return json(
        {
          error: 'No credentials registered. Please register a credential first.',
          code: 'NO_CREDENTIALS'
        },
        { status: 400 }
      );
    }

    // Generate authentication options
    const { options, challenge } = await service.generateAuthenticationOptions(credentials);

    // Store challenge for verification
    await store.setChallenge(challenge);

    return json(options);
  } catch (error) {
    console.error('Authentication options error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    return json(
      {
        error: message,
        code: 'AUTHENTICATION_OPTIONS_FAILED'
      },
      { status: 500 }
    );
  }
};
