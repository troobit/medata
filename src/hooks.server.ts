/**
 * SvelteKit server hooks
 *
 * Handles session validation for protected routes.
 */

import type { Handle } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';

import { createSessionConfig, getSessionService } from '$lib/server/auth';
import type { SessionData } from '$lib/server/auth';

// Declare session type in app locals
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace App {
    interface Locals {
      session: SessionData | null;
    }
  }
}

export const handle: Handle = async ({ event, resolve }) => {
  // Default to no session
  event.locals.session = null;

  // createSessionConfig returns null during prerender when env vars aren't available
  const sessionConfig = createSessionConfig(env);

  if (sessionConfig) {
    try {
      const sessionService = getSessionService(sessionConfig);

      // Get session cookie
      const cookieOptions = sessionService.getCookieOptions();
      const token = event.cookies.get(cookieOptions.name);

      if (token) {
        // Validate session
        const sessionData = sessionService.validateSession(token);
        if (sessionData) {
          event.locals.session = sessionData;
        }
      }
    } catch (error) {
      // Log error but don't block request - just leave session as null
      console.error('Session validation error in hooks:', error);
    }
  }

  return resolve(event);
};
