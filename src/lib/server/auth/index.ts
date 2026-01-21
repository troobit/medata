/**
 * Server-side authentication module
 */

import { FileCredentialStore, getFileCredentialStore } from './FileCredentialStore';

export { WebAuthnService, createWebAuthnConfig } from './WebAuthnService';
export { FileCredentialStore, getFileCredentialStore };
export { SessionService, createSessionConfig, getSessionService } from './SessionService';
export { BootstrapService, createBootstrapConfig } from './bootstrap';
export type { ICredentialStore } from './ICredentialStore';
export type { BootstrapConfig, BootstrapState } from './bootstrap';
export type {
  StoredCredential,
  StoredChallenge,
  CredentialStoreData,
  WebAuthnConfig,
  RegistrationOptionsResponse,
  RegistrationVerifyRequest,
  RegistrationVerifyResponse,
  AuthErrorResponse,
  AuthenticationOptionsResponse,
  AuthenticationVerifyResponse,
  SessionData,
  SessionStatusResponse,
  SessionConfig
} from './types';

// Backward compatibility - alias for getFileCredentialStore
export const getCredentialStore = getFileCredentialStore;
