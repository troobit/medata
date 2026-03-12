/**
 * Re-export all services from the services directory.
 *
 * NOTE: claude-food-recognition.ts is intentionally NOT exported here
 * because it imports $env/dynamic/private which cannot be used in
 * browser code. Import it directly in server routes:
 *   import { ClaudeFoodRecognitionService } from '$lib/services/claude-food-recognition.js';
 */
export * from './food-recognition.js';
export * from './recognition.js';
export * from './meal-api.js';
export * from './preset-api.js';
