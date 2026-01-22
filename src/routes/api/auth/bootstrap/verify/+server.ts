/**
 * POST /api/auth/bootstrap/verify
 *
 * Verify WebAuthn registration attestation and store the first credential.
 * Only available when no credentials exist and valid bootstrap token is provided.
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { RegistrationResponseJSON } from '@simplewebauthn/server';
import { env } from '$env/dynamic/private';

import {
  WebAuthnService,
  createWebAuthnConfig,
  getCredentialStore,
  BootstrapService,
  createBootstrapConfig,
  createSessionConfig,
  getSessionService
} from '$lib/server/auth';

interface BootstrapVerifyRequest {
  bootstrapToken: string;
  credential: RegistrationResponseJSON;
  friendlyName?: string;
}

export const POST: RequestHandler = async ({ request, cookies }) => {
  try {
    const configResult = createWebAuthnConfig(env);

    if (!configResult.success) {
      return json(
        { error: configResult.error, code: configResult.code },
        { status: 503 }
      );
    }

    const store = getCredentialStore();
    const bootstrapConfig = createBootstrapConfig(env);
    const bootstrapService = new BootstrapService(store, bootstrapConfig);

    // Parse request body
    const body = (await request.json()) as BootstrapVerifyRequest;

    if (!body.bootstrapToken) {
      return json(
        {
          error: 'Bootstrap token is required',
          code: 'MISSING_TOKEN'
        },
        { status: 400 }
      );
    }

    if (!body.credential) {
      return json(
        {
          error: 'Missing credential in request body',
          code: 'INVALID_REQUEST'
        },
        { status: 400 }
      );
    }

    // Verify bootstrap is allowed
    await bootstrapService.verifyBootstrapAllowed(body.bootstrapToken);

    // Get stored challenge
    const storedChallenge = await store.getChallenge();

    if (!storedChallenge) {
      return json(
        {
          error: 'No registration challenge found. Please start bootstrap again.',
          code: 'NO_CHALLENGE'
        },
        { status: 400 }
      );
    }

    const service = new WebAuthnService(configResult.config);

    // Verify the registration response
    const credential = await service.verifyRegistration(
      body.credential,
      storedChallenge,
      body.friendlyName || 'Primary Hardware Key'
    );

    // Store the verified credential
    await store.addCredential(credential);

    // Clear the used challenge
    await store.clearChallenge();

    // Create a session for the newly enrolled user
    const sessionConfig = createSessionConfig(env);

    if (!sessionConfig) {
      return json(
        {
          error:
            'Session configuration unavailable. Check AUTH_SESSION_SECRET environment variable.',
          code: 'CONFIG_ERROR'
        },
        { status: 500 }
      );
    }

    const sessionService = getSessionService(sessionConfig);
    const { token, expiresAt } = sessionService.createSession(credential.id);

    // Set session cookie
    const cookieOptions = sessionService.getCookieOptions();
    cookies.set(cookieOptions.name, token, {
      path: cookieOptions.path,
      httpOnly: cookieOptions.httpOnly,
      secure: cookieOptions.secure,
      sameSite: cookieOptions.sameSite,
      maxAge: cookieOptions.maxAge
    });

    return json({
      verified: true,
      credentialId: credential.id,
      expiresAt: new Date(expiresAt * 1000).toISOString()
    });
  } catch (error) {
    console.error('Bootstrap verification error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    // Determine appropriate status code
    const status =
      message.includes('not available') || message.includes('already exist')
        ? 400
        : message.includes('Invalid bootstrap token')
          ? 401
          : message.includes('expired') || message.includes('Challenge')
            ? 400
            : message.includes('failed')
              ? 400
              : 500;

    return json(
      {
        error: message,
        code: 'BOOTSTRAP_VERIFICATION_FAILED'
      },
      { status }
    );
  }
};
