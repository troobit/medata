/**
 * Favicon.ico fallback endpoint
 *
 * Redirects legacy favicon.ico requests to the default SVG favicon.
 * This prevents 404 errors from browsers that automatically request /favicon.ico.
 */
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = () => {
  // Redirect to the default SVG favicon
  redirect(301, '/favicon-default.svg');
};

// Allow prerendering
export const prerender = true;
