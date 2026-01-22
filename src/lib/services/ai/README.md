# Workstream A: AI Food Recognition Services

**Branch**: `workstream-a/food-ai`

This directory contains cloud AI-based food recognition service implementations.

## Interface

Implement `IFoodRecognitionService` from `$lib/types/ai.ts`

## Files to create

- `FoodServiceFactory.ts` - Factory for selecting provider
- `OpenAIFoodService.ts` - OpenAI Vision (GPT-4V) implementation
- `GeminiFoodService.ts` - Google Gemini Pro Vision implementation
- `ClaudeFoodService.ts` - Anthropic Claude Vision implementation
- `OllamaFoodService.ts` - Self-hosted Ollama/LLaVA implementation
- `prompts/foodRecognition.ts` - Structured prompts for consistent output

## Usage

```typescript
import { FoodServiceFactory } from '$lib/services/ai';

const service = FoodServiceFactory.create(settings);
const result = await service.RecogniseFood(imageBlob);
```
