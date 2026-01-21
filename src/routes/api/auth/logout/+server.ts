/**
 * POST /api/auth/logout
 *
 * Clear the session cookie and logout the user.
 */

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';

import { createSessionConfig, getSessionService } from '$lib/server/auth';

export const POST: RequestHandler = async ({ cookies }) => {
  try {
    const sessionConfig = createSessionConfig(env);

    if (!sessionConfig) {
      return json(
        {
          error: 'Session configuration unavailable. Check AUTH_SESSION_SECRET environment variable.',
          code: 'CONFIG_ERROR'
        },
        { status: 500 }
      );
    }

    const sessionService = getSessionService(sessionConfig);

    // Clear session cookie
    const cookieOptions = sessionService.getClearCookieOptions();
    cookies.set(cookieOptions.name, '', {
      path: cookieOptions.path,
      httpOnly: cookieOptions.httpOnly,
      secure: cookieOptions.secure,
      sameSite: cookieOptions.sameSite,
      maxAge: cookieOptions.maxAge
    });

    return json({ success: true });
  } catch (error) {
    console.error('Logout error:', error);

    const message = error instanceof Error ? error.message : 'Unknown error';

    return json(
      {
        error: message,
        code: 'LOGOUT_FAILED'
      },
      { status: 500 }
    );
  }
};
