/**
 * Server-side authentication module
 */

export { WebAuthnService, createWebAuthnConfig } from './WebAuthnService';
export { FileCredentialStore, getFileCredentialStore } from './FileCredentialStore';
export { KVCredentialStore, getKVCredentialStore } from './KVCredentialStore';
export {
  getCredentialStore,
  isKVStorageAvailable,
  clearCredentialStoreCache
} from './credentialStoreFactory';
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
