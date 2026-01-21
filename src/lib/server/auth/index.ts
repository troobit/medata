/**
 * Server-side authentication module
 */

export { WebAuthnService, createWebAuthnConfig } from './WebAuthnService';
export { CredentialStore, getCredentialStore } from './CredentialStore';
export type {
  StoredCredential,
  StoredChallenge,
  CredentialStoreData,
  WebAuthnConfig,
  RegistrationOptionsResponse,
  RegistrationVerifyRequest,
  RegistrationVerifyResponse,
  AuthErrorResponse
} from './types';
