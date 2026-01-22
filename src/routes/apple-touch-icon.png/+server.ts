/**
 * Apple touch icon fallback endpoint
 *
 * Redirects bare apple-touch-icon.png requests to the default variant.
 * This prevents 404 errors from browsers that automatically request /apple-touch-icon.png.
 */
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = () => {
  // Redirect to the default apple touch icon
  redirect(301, '/apple-touch-icon-default.png');
};

// Allow prerendering
export const prerender = true;
