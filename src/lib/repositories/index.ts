/**
 * Re-export all repository interfaces and implementations.
 */

// Interfaces
export type { IMealRepository } from './meal-repository.js';
export type { IImageRepository, ImageFolder } from './image-repository.js';

// Implementations
export { CosmosMealRepository, getMealRepository } from './cosmos-meal-repository.js';
export { BlobImageRepository, getImageRepository } from './blob-image-repository.js';
