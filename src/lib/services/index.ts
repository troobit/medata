export { EventService } from './EventService';
export { SettingsService } from './SettingsService';
export { VisionService, VisionServiceError, getVisionService } from './VisionService';
export { BSLRecognitionService, getBSLRecognitionService } from './BSLRecognitionService';

// Factory functions with default repositories
import { EventService } from './EventService';
import { SettingsService } from './SettingsService';
import { getEventRepository, getSettingsRepository } from '$lib/repositories';

let eventService: EventService | null = null;
let settingsService: SettingsService | null = null;

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
