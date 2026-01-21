/**
 * Server-side authentication types for WebAuthn
 */

import type {
  AuthenticatorTransportFuture,
  CredentialDeviceType
} from '@simplewebauthn/server';

/**
 * Stored credential for a registered authenticator
 */
export interface StoredCredential {
  id: string; // base64url encoded credential ID
  publicKey: string; // base64url encoded public key
  counter: number;
  deviceType: CredentialDeviceType;
  backedUp: boolean;
  transports?: AuthenticatorTransportFuture[];
  friendlyName: string;
  createdAt: string; // ISO timestamp
  lastUsedAt: string | null; // ISO timestamp
}

/**
 * Challenge stored temporarily during registration/authentication
 */
export interface StoredChallenge {
  challenge: string; // base64url encoded
  expiresAt: number; // Unix timestamp
}

/**
 * Credential store data structure
 */
export interface CredentialStoreData {
  credentials: StoredCredential[];
  currentChallenge?: StoredChallenge;
}

/**
 * WebAuthn configuration from environment
 */
export interface WebAuthnConfig {
  rpId: string;
  rpName: string;
  origin: string;
  credentialsPath: string;
}

/**
 * Registration options response sent to client
 */
export interface RegistrationOptionsResponse {
  challenge: string;
  rp: {
    id: string;
    name: string;
  };
  user: {
    id: string;
    name: string;
    displayName: string;
  };
  pubKeyCredParams: Array<{
    type: 'public-key';
    alg: number;
  }>;
  timeout: number;
  attestation: 'none';
  authenticatorSelection: {
    residentKey: 'preferred';
    userVerification: 'preferred';
    authenticatorAttachment?: 'cross-platform';
  };
  excludeCredentials: Array<{
    id: string;
    type: 'public-key';
    transports?: AuthenticatorTransportFuture[];
  }>;
}

/**
 * Registration verification request from client
 */
export interface RegistrationVerifyRequest {
  id: string;
  rawId: string;
  response: {
    clientDataJSON: string;
    attestationObject: string;
    transports?: AuthenticatorTransportFuture[];
  };
  type: 'public-key';
  clientExtensionResults: Record<string, unknown>;
  authenticatorAttachment?: 'cross-platform' | 'platform';
}

/**
 * Registration verification response
 */
export interface RegistrationVerifyResponse {
  verified: boolean;
  credentialId?: string;
}

/**
 * API error response
 */
export interface AuthErrorResponse {
  error: string;
  code: string;
}
