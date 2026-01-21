/**
 * WebAuthnService - Server-side WebAuthn verification logic
 *
 * Framework-agnostic service for WebAuthn operations.
 * Handles registration options generation and attestation verification.
 */

import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse
} from '@simplewebauthn/server';
import type {
  GenerateRegistrationOptionsOpts,
  VerifyRegistrationResponseOpts,
  GenerateAuthenticationOptionsOpts,
  VerifyAuthenticationResponseOpts
} from '@simplewebauthn/server';
import type { RegistrationResponseJSON, AuthenticationResponseJSON } from '@simplewebauthn/server';
import { isoBase64URL } from '@simplewebauthn/server/helpers';

import type {
  WebAuthnConfig,
  StoredCredential,
  RegistrationOptionsResponse,
  StoredChallenge,
  AuthenticationOptionsResponse
} from './types';

// Challenge expiry time: 5 minutes
const CHALLENGE_EXPIRY_MS = 5 * 60 * 1000;

// Single user identity for this single-user application
// Note: USER_ID is reserved for future use when user identification is needed
const _USER_ID = 'owner';
const USER_NAME = 'owner';
const USER_DISPLAY_NAME = 'Owner';

export class WebAuthnService {
  private config: WebAuthnConfig;

  constructor(config: WebAuthnConfig) {
    this.config = config;
  }

  /**
   * Generate registration options for a new credential
   */
  async generateRegistrationOptions(
    existingCredentials: StoredCredential[]
  ): Promise<{ options: RegistrationOptionsResponse; challenge: StoredChallenge }> {
    const opts: GenerateRegistrationOptionsOpts = {
      rpName: this.config.rpName,
      rpID: this.config.rpId,
      userName: USER_NAME,
      userDisplayName: USER_DISPLAY_NAME,
      timeout: 60000,
      attestationType: 'none',
      excludeCredentials: existingCredentials.map((cred) => ({
        id: cred.id,
        transports: cred.transports
      })),
      authenticatorSelection: {
        residentKey: 'preferred',
        userVerification: 'preferred',
        authenticatorAttachment: 'cross-platform'
      },
      supportedAlgorithmIDs: [-7, -257] // ES256, RS256
    };

    const registrationOptions = await generateRegistrationOptions(opts);

    // Store challenge with expiry
    const challenge: StoredChallenge = {
      challenge: registrationOptions.challenge,
      expiresAt: Date.now() + CHALLENGE_EXPIRY_MS
    };

    // Transform to our response format
    const options: RegistrationOptionsResponse = {
      challenge: registrationOptions.challenge,
      rp: {
        id: this.config.rpId,
        name: this.config.rpName
      },
      user: {
        id: registrationOptions.user.id,
        name: registrationOptions.user.name,
        displayName: registrationOptions.user.displayName
      },
      pubKeyCredParams: registrationOptions.pubKeyCredParams.map((p) => ({
        type: 'public-key' as const,
        alg: p.alg
      })),
      timeout: registrationOptions.timeout ?? 60000,
      attestation: 'none',
      authenticatorSelection: {
        residentKey: 'preferred',
        userVerification: 'preferred',
        authenticatorAttachment: 'cross-platform'
      },
      excludeCredentials:
        registrationOptions.excludeCredentials?.map((cred) => ({
          id: cred.id,
          type: 'public-key' as const,
          transports: cred.transports
        })) ?? []
    };

    return { options, challenge };
  }

  /**
   * Verify registration response and return credential to store
   */
  async verifyRegistration(
    response: RegistrationResponseJSON,
    storedChallenge: StoredChallenge,
    friendlyName: string = 'Hardware Key'
  ): Promise<StoredCredential> {
    // Check challenge expiry
    if (Date.now() > storedChallenge.expiresAt) {
      throw new Error('Challenge expired');
    }

    const opts: VerifyRegistrationResponseOpts = {
      response,
      expectedChallenge: storedChallenge.challenge,
      expectedOrigin: this.config.origin,
      expectedRPID: this.config.rpId,
      requireUserVerification: false
    };

    const verification = await verifyRegistrationResponse(opts);

    if (!verification.verified || !verification.registrationInfo) {
      throw new Error('Registration verification failed');
    }

    const { credential, credentialDeviceType, credentialBackedUp } = verification.registrationInfo;

    const storedCredential: StoredCredential = {
      id: credential.id,
      publicKey: isoBase64URL.fromBuffer(credential.publicKey),
      counter: credential.counter,
      deviceType: credentialDeviceType,
      backedUp: credentialBackedUp,
      transports: credential.transports,
      friendlyName,
      createdAt: new Date().toISOString(),
      lastUsedAt: null
    };

    return storedCredential;
  }

  /**
   * Generate authentication options for login
   */
  async generateAuthenticationOptions(
    credentials: StoredCredential[]
  ): Promise<{ options: AuthenticationOptionsResponse; challenge: StoredChallenge }> {
    if (credentials.length === 0) {
      throw new Error('No credentials registered');
    }

    const opts: GenerateAuthenticationOptionsOpts = {
      rpID: this.config.rpId,
      timeout: 60000,
      allowCredentials: credentials.map((cred) => ({
        id: cred.id,
        transports: cred.transports
      })),
      userVerification: 'preferred'
    };

    const authOptions = await generateAuthenticationOptions(opts);

    // Store challenge with expiry
    const challenge: StoredChallenge = {
      challenge: authOptions.challenge,
      expiresAt: Date.now() + CHALLENGE_EXPIRY_MS
    };

    // Transform to our response format
    const options: AuthenticationOptionsResponse = {
      challenge: authOptions.challenge,
      rpId: this.config.rpId,
      allowCredentials:
        authOptions.allowCredentials?.map((cred) => ({
          id: cred.id,
          type: 'public-key' as const,
          transports: cred.transports
        })) ?? [],
      timeout: authOptions.timeout ?? 60000,
      userVerification: 'preferred'
    };

    return { options, challenge };
  }

  /**
   * Verify authentication response and return verification result with updated counter
   */
  async verifyAuthentication(
    response: AuthenticationResponseJSON,
    storedChallenge: StoredChallenge,
    credential: StoredCredential
  ): Promise<{ verified: boolean; newCounter: number }> {
    // Check challenge expiry
    if (Date.now() > storedChallenge.expiresAt) {
      throw new Error('Challenge expired');
    }

    const opts: VerifyAuthenticationResponseOpts = {
      response,
      expectedChallenge: storedChallenge.challenge,
      expectedOrigin: this.config.origin,
      expectedRPID: this.config.rpId,
      credential: {
        id: credential.id,
        publicKey: isoBase64URL.toBuffer(credential.publicKey),
        counter: credential.counter,
        transports: credential.transports
      },
      requireUserVerification: false
    };

    const verification = await verifyAuthenticationResponse(opts);

    if (!verification.verified) {
      throw new Error('Authentication verification failed');
    }

    // Validate counter to prevent replay attacks
    const newCounter = verification.authenticationInfo.newCounter;
    if (newCounter <= credential.counter) {
      throw new Error('Counter validation failed: possible replay attack');
    }

    return {
      verified: true,
      newCounter
    };
  }
}

/**
 * Create WebAuthn config from environment variables
 * @param env - Environment variables from $env/dynamic/private
 */
export function createWebAuthnConfig(env: Record<string, string | undefined>): WebAuthnConfig {
  const rpId = env.AUTH_RP_ID;
  const origin = env.AUTH_ORIGIN;

  if (!rpId) {
    throw new Error('AUTH_RP_ID environment variable is required');
  }

  if (!origin) {
    throw new Error('AUTH_ORIGIN environment variable is required');
  }

  return {
    rpId,
    rpName: 'Beetus',
    origin
  };
}
