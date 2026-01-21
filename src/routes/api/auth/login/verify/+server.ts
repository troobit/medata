/**
 * POST /api/auth/login/verify
 *
 * Verify WebAuthn authentication assertion and create session.
 * Receives the result of navigator.credentials.get() from the client.
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { AuthenticationResponseJSON } from '@simplewebauthn/server';
import { env } from '$env/dynamic/private';

import {
  WebAuthnService,
  createWebAuthnConfig,
  getCredentialStore,
  createSessionConfig,
  getSessionService
} from '$lib/server/auth';

interface VerifyRequestBody {
  credential: AuthenticationResponseJSON;
}

export const POST: RequestHandler = async ({ request, cookies }) => {
  try {
    const config = createWebAuthnConfig(env);
    const store = getCredentialStore(config.credentialsPath);
    const service = new WebAuthnService(config);
    const sessionConfig = createSessionConfig(env);
    const sessionService = getSessionService(sessionConfig);

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
          error: 'No authentication challenge found. Please start authentication again.',
          code: 'NO_CHALLENGE'
        },
        { status: 400 }
      );
    }

    // Find the credential used for authentication
    const credentialId = body.credential.id;
    const storedCredential = await store.getCredentialById(credentialId);

    if (!storedCredential) {
      return json(
        {
          error: 'Credential not found',
          code: 'CREDENTIAL_NOT_FOUND'
        },
        { status: 400 }
      );
    }

    // Verify the authentication response (includes counter validation)
    const { newCounter } = await service.verifyAuthentication(
      body.credential,
      storedChallenge,
      storedCredential
    );

    // Update credential counter and lastUsedAt
    await store.updateCredential(credentialId, {
      counter: newCounter,
      lastUsedAt: new Date().toISOString()
    });

    // Clear the used challenge
    await store.clearChallenge();

    // Create session
    const { token, expiresAt } = sessionService.createSession(credentialId);

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
      expiresAt: new Date(expiresAt * 1000).toISOString()
    });
  } catch (error) {
    console.error('Authentication verification error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    // Determine appropriate status code
    const status =
      message.includes('expired') || message.includes('Challenge')
        ? 400
        : message.includes('failed') || message.includes('Counter')
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
