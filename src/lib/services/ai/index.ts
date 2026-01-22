/**
 * Workstream A: AI Food Recognition Services
 * Branch: dev-1
 */

export { OpenAIFoodService } from './OpenAIFoodService';
export { GeminiFoodService } from './GeminiFoodService';
export { ClaudeFoodService } from './ClaudeFoodService';
export {
  createFoodService,
  getFoodService,
  getAllConfiguredServices,
  RecogniseFoodWithFallback,
  isAnyProviderConfigured,
  getPrimaryProviderName
} from './FoodServiceFactory';
export {
  FOOD_RECOGNITION_SYSTEM_PROMPT,
  FOOD_RECOGNITION_USER_PROMPT,
  NUTRITION_LABEL_SYSTEM_PROMPT,
  NUTRITION_LABEL_USER_PROMPT,
  parseAIResponse
} from './prompts/foodRecognition';
