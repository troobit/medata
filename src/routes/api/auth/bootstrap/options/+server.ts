/**
 * POST /api/auth/bootstrap/options
 *
 * Generate WebAuthn registration options for initial credential enrollment.
 * Only available when no credentials exist and valid bootstrap token is provided.
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

import {
  WebAuthnService,
  createWebAuthnConfig,
  getCredentialStore,
  BootstrapService,
  createBootstrapConfig
} from '$lib/server/auth';

interface BootstrapOptionsRequest {
  bootstrapToken: string;
}

export const POST: RequestHandler = async ({ request }) => {
  try {
    const config = createWebAuthnConfig(env);
    const store = getCredentialStore(config.credentialsPath);
    const bootstrapConfig = createBootstrapConfig(env);
    const bootstrapService = new BootstrapService(store, bootstrapConfig);

    // Parse request body
    const body = (await request.json()) as BootstrapOptionsRequest;

    if (!body.bootstrapToken) {
      return json(
        {
          error: 'Bootstrap token is required',
          code: 'MISSING_TOKEN'
        },
        { status: 400 }
      );
    }

    // Verify bootstrap is allowed
    await bootstrapService.verifyBootstrapAllowed(body.bootstrapToken);

    const service = new WebAuthnService(config);

    // Generate registration options (no existing credentials for bootstrap)
    const { options, challenge } = await service.generateRegistrationOptions([]);

    // Store challenge for verification
    await store.setChallenge(challenge);

    return json(options);
  } catch (error) {
    console.error('Bootstrap options error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    // Determine appropriate status code
    const status =
      message.includes('not available') || message.includes('already exist')
        ? 400
        : message.includes('Invalid bootstrap token')
          ? 401
          : 500;

    return json(
      {
        error: message,
        code: 'BOOTSTRAP_OPTIONS_FAILED'
      },
      { status }
    );
  }
};
