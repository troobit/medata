import { prefersReducedMotion } from 'svelte/motion';

/**
 * Returns 0ms if user prefers reduced motion, otherwise returns the provided duration.
 * Use this to respect user accessibility preferences for animations.
 */
export function getAnimationDuration(durationMs: number): number {
  return prefersReducedMotion.current ? 0 : durationMs;
}
