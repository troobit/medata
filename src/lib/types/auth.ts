/**
 * Authentication Types
 * Task 24: FIDO/YubiKey authentication for multi-user support
 *
 * Uses WebAuthn API for passwordless authentication
 * with hardware security keys (YubiKey, Passkeys, etc.)
 */

/**
 * User account stored locally
 */
export interface User {
  id: string;
  username: string;
  displayName: string;
  createdAt: Date;
  lastLoginAt?: Date;
}

/**
 * WebAuthn credential stored for a user
 */
export interface StoredCredential {
  credentialId: string; // Base64 encoded
  userId: string;
  publicKey: string; // Base64 encoded COSE key
  counter: number;
  deviceType: 'platform' | 'cross-platform';
  createdAt: Date;
  lastUsedAt?: Date;
  friendlyName?: string; // e.g., "YubiKey 5", "iPhone Passkey"
}

/**
 * Authentication session
 */
export interface AuthSession {
  userId: string;
  username: string;
  expiresAt: Date;
  credentialId?: string;
}

/**
 * Challenge for WebAuthn registration/authentication
 */
export interface AuthChallenge {
  challenge: string; // Base64 encoded random bytes
  userId: string;
  timeout: number; // milliseconds
  createdAt: Date;
}

/**
 * WebAuthn registration options
 */
export interface RegistrationOptions {
  challenge: ArrayBuffer;
  rp: {
    name: string;
    id?: string;
  };
  user: {
    id: ArrayBuffer;
    name: string;
    displayName: string;
  };
  pubKeyCredParams: PublicKeyCredentialParameters[];
  timeout?: number;
  attestation?: AttestationConveyancePreference;
  authenticatorSelection?: AuthenticatorSelectionCriteria;
  excludeCredentials?: PublicKeyCredentialDescriptor[];
}

/**
 * WebAuthn authentication options
 */
export interface AuthenticationOptions {
  challenge: ArrayBuffer;
  timeout?: number;
  rpId?: string;
  allowCredentials?: PublicKeyCredentialDescriptor[];
  userVerification?: UserVerificationRequirement;
}

/**
 * Result of WebAuthn registration
 */
export interface RegistrationResult {
  credentialId: string;
  publicKey: string;
  attestationObject: string;
  clientDataJSON: string;
}

/**
 * Result of WebAuthn authentication
 */
export interface AuthenticationResult {
  credentialId: string;
  authenticatorData: string;
  clientDataJSON: string;
  signature: string;
  userHandle?: string;
}

/**
 * Configuration for authentication
 */
export interface AuthConfig {
  enabled: boolean;
  rpName: string; // Relying party name (app name)
  rpId?: string; // Relying party ID (domain)
  timeout: number; // milliseconds
  userVerification: UserVerificationRequirement;
  authenticatorAttachment?: AuthenticatorAttachment;
  residentKey?: ResidentKeyRequirement;
}

/**
 * Default authentication configuration
 */
export const DEFAULT_AUTH_CONFIG: AuthConfig = {
  enabled: false, // Disabled by default (Phase 1)
  rpName: 'MeData',
  timeout: 60000, // 60 seconds
  userVerification: 'preferred',
  authenticatorAttachment: 'cross-platform', // Prefer hardware keys
  residentKey: 'preferred'
};

/**
 * Authentication error codes
 */
export type AuthErrorCode =
  | 'NOT_SUPPORTED' // WebAuthn not supported
  | 'NOT_ALLOWED' // User denied request
  | 'TIMEOUT' // Operation timed out
  | 'INVALID_STATE' // Authenticator already registered
  | 'INVALID_CREDENTIAL' // Credential not found
  | 'UNKNOWN_ERROR';

/**
 * Authentication error
 */
export class AuthError extends Error {
  constructor(
    public code: AuthErrorCode,
    message: string
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

/**
 * Check if WebAuthn is supported in this browser
 */
export function isWebAuthnSupported(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.PublicKeyCredential !== 'undefined' &&
    typeof window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable === 'function'
  );
}

/**
 * Check if platform authenticator is available (TouchID, FaceID, Windows Hello)
 */
export async function isPlatformAuthenticatorAvailable(): Promise<boolean> {
  if (!isWebAuthnSupported()) return false;
  try {
    return await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
  } catch {
    return false;
  }
}

/**
 * Convert ArrayBuffer to Base64 string
 */
export function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

/**
 * Convert Base64 string to ArrayBuffer
 */
export function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

/**
 * Generate a random challenge
 */
export function generateChallenge(): ArrayBuffer {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return array.buffer;
}
