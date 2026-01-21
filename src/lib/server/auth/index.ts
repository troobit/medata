/**
 * Server-side authentication module
 */

export { WebAuthnService, createWebAuthnConfig } from './WebAuthnService';
export { FileCredentialStore, getFileCredentialStore } from './FileCredentialStore';
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

// Backward compatibility alias
export { FileCredentialStore as CredentialStore } from './FileCredentialStore';
export { getFileCredentialStore as getCredentialStore } from './FileCredentialStore';
