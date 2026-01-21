/**
 * Server-side authentication module
 */

export { WebAuthnService, createWebAuthnConfig } from './WebAuthnService';
export { CredentialStore, getCredentialStore } from './CredentialStore';
export { SessionService, createSessionConfig, getSessionService } from './SessionService';
export { BootstrapService, createBootstrapConfig } from './bootstrap';
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
