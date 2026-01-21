/**
 * GET /api/auth/session
 *
 * Check current session validity and return session status.
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

import { createSessionConfig, getSessionService } from '$lib/server/auth';
import type { SessionStatusResponse } from '$lib/server/auth';

export const GET: RequestHandler = async ({ cookies }) => {
  try {
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

    // Get session cookie
    const cookieOptions = sessionService.getCookieOptions();
    const token = cookies.get(cookieOptions.name);

    if (!token) {
      const response: SessionStatusResponse = {
        authenticated: false,
        expiresAt: null
      };
      return json(response);
    }

    // Validate session
    const sessionData = sessionService.validateSession(token);

    if (!sessionData) {
      const response: SessionStatusResponse = {
        authenticated: false,
        expiresAt: null
      };
      return json(response);
    }

    const response: SessionStatusResponse = {
      authenticated: true,
      expiresAt: new Date(sessionData.expiresAt * 1000).toISOString()
    };

    return json(response);
  } catch (error) {
    console.error('Session check error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    return json(
      {
        error: message,
        code: 'SESSION_CHECK_FAILED'
      },
      { status: 500 }
    );
  }
};
