export { EventService } from './EventService';
export { SettingsService } from './SettingsService';
export { VisionService, VisionServiceError, getVisionService } from './VisionService';
export { BSLRecognitionService, getBSLRecognitionService } from './BSLRecognitionService';
export { ValidationService } from './ValidationService';

// Modeling services
export * from './modeling';

// Factory functions with default repositories
import { EventService } from './EventService';
import { SettingsService } from './SettingsService';
import { ValidationService } from './ValidationService';
import {
  getEventRepository,
  getSettingsRepository,
  getValidationRepository
} from '$lib/repositories';

let eventService: EventService | null = null;
let settingsService: SettingsService | null = null;
let validationService: ValidationService | null = null;

export function getEventService(): EventService {
  if (!eventService) {
    eventService = new EventService(getEventRepository());
  }
  return eventService;
}

export function getSettingsService(): SettingsService {
  if (!settingsService) {
    settingsService = new SettingsService(getSettingsRepository());
  }
  return settingsService;
}

export function getValidationService(): ValidationService {
  if (!validationService) {
    validationService = new ValidationService(getValidationRepository());
  }
  return validationService;
}
