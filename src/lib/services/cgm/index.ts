/**
 * Workstream B: CGM Graph Image Capture Services
 * Branch: dev-2
 *
 * This module provides services for extracting BSL data from CGM app screenshots.
 *
 * Extraction methods:
 * - ML-assisted: Uses cloud vision APIs (OpenAI, Claude, Gemini, Ollama, Foundry)
 * - Local CV: Uses browser-based computer vision (no API required)
 * - Direct API: Connects to CGM cloud services (LibreLink, Dexcom Share)
 *
 * Device-specific parsers:
 * - LibreGraphParser: Optimized for Freestyle Libre screenshots
 * - DexcomGraphParser: Optimized for Dexcom G6/G7 screenshots
 */

// Main processor with ML and local CV support
export {
  CGMImageProcessor,
  createCGMImageProcessor,
  type ExtendedCGMExtractionOptions
} from './CGMImageProcessor';

// Local computer vision extractor (Phase 2)
export { LocalCurveExtractor, createLocalCurveExtractor } from './LocalCurveExtractor';

// Device-specific parsers (Phase 2)
export { LibreGraphParser, createLibreGraphParser } from './LibreGraphParser';
export { DexcomGraphParser, createDexcomGraphParser } from './DexcomGraphParser';

// Direct CGM API Services (Task 22)
export { LibreLinkApiService, createLibreLinkApiService } from './LibreLinkApiService';
export { DexcomShareApiService, createDexcomShareApiService } from './DexcomShareApiService';
export {
  createCGMApiService,
  isCGMApiConfigured,
  getCGMProviderName,
  CGM_PROVIDERS
} from './CGMApiFactory';
