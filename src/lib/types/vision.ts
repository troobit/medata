/**
 * Vision/image recognition types for BSL extraction
 */

import type { BSLUnit } from './events';

/**
 * Individual extracted BSL reading from an image
 */
export interface ExtractedBSLReading {
  value: number;
  unit: BSLUnit;
  timestamp: Date;
  confidence: number; // 0-1 confidence score
  rawText?: string; // Original text extracted from image
}

/**
 * Result container for BSL extraction from an image
 */
export interface BSLExtractionResult {
  readings: ExtractedBSLReading[];
  imageMetadata?: {
    source?: string; // e.g., 'libre', 'dexcom', 'unknown'
    dimensions?: { width: number; height: number };
  };
  error?: string;
}

/**
 * Options for vision API analysis
 */
export interface VisionAnalysisOptions {
  maxTokens?: number;
  model?: string;
}

/**
 * OpenAI Vision API response structure
 */
export interface OpenAIVisionResponse {
  id: string;
  choices: Array<{
    message: {
      content: string;
    };
    finish_reason: string;
  }>;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}
