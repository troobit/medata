# AI Food Recognition Services

Cloud AI-based food recognition service implementations.

## Interface

Implements `IFoodRecognitionService` from `$lib/types/ai.ts`

## Files

- `FoodServiceFactory.ts` - Factory for selecting provider
- `OpenAIFoodService.ts` - OpenAI Vision (GPT-4V) implementation
- `GeminiFoodService.ts` - Google Gemini Pro Vision implementation
- `ClaudeFoodService.ts` - Anthropic Claude Vision implementation
- `LocalFoodService.ts` - Self-hosted Ollama/LLaVA implementation
- `AzureFoodService.ts` - Azure OpenAI implementation
- `AzureFoundryFoodService.ts` - Azure AI Foundry implementation
- `BedrockFoodService.ts` - AWS Bedrock implementation
- `prompts/foodRecognition.ts` - Structured prompts for consistent output

## Usage

```typescript
import { FoodServiceFactory } from '$lib/services/ai';

const service = FoodServiceFactory.create(settings);
const result = await service.recogniseFood(imageBlob);
```
