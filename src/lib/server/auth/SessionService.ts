/**
 * SessionService - Secure session management with signed cookies
 *
 * Handles session creation, validation, and destruction using
 * HMAC-signed cookies for single-user authentication.
 */

import { createHmac, timingSafeEqual } from 'node:crypto';

import type { SessionData, SessionConfig } from './types';

// Single user ID constant
const USER_ID = 'owner';

// Default session duration: 7 days
const DEFAULT_MAX_AGE = 7 * 24 * 60 * 60;

export class SessionService {
  private config: SessionConfig;

  constructor(config: SessionConfig) {
    this.config = config;
  }

  /**
   * Create a signed session token
   */
  createSession(credentialId: string): { token: string; expiresAt: number } {
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + this.config.maxAge;

    const sessionData: SessionData = {
      userId: USER_ID,
      credentialId,
      createdAt: now,
      expiresAt
    };

    const payload = JSON.stringify(sessionData);
    const signature = this.sign(payload);
    const token = `${this.base64UrlEncode(payload)}.${signature}`;

    return { token, expiresAt };
  }

  /**
   * Validate and decode a session token
   */
  validateSession(token: string): SessionData | null {
    try {
      const [payloadB64, signature] = token.split('.');

      if (!payloadB64 || !signature) {
        return null;
      }

      const payload = this.base64UrlDecode(payloadB64);

      // Verify signature using timing-safe comparison
      const expectedSignature = this.sign(payload);
      if (!this.timingSafeCompare(signature, expectedSignature)) {
        return null;
      }

      const sessionData = JSON.parse(payload) as SessionData;

      // Check expiry
      const now = Math.floor(Date.now() / 1000);
      if (sessionData.expiresAt < now) {
        return null;
      }

      return sessionData;
    } catch {
      return null;
    }
  }

  /**
   * Get cookie options for setting the session cookie
   */
  getCookieOptions(): {
    name: string;
    path: string;
    httpOnly: boolean;
    secure: boolean;
    sameSite: 'lax' | 'strict' | 'none';
    maxAge: number;
  } {
    return {
      name: this.config.cookieName,
      path: '/',
      httpOnly: true,
      secure: this.config.secure,
      sameSite: 'lax',
      maxAge: this.config.maxAge
    };
  }

  /**
   * Get cookie options for clearing the session cookie
   */
  getClearCookieOptions(): {
    name: string;
    path: string;
    httpOnly: boolean;
    secure: boolean;
    sameSite: 'lax' | 'strict' | 'none';
    maxAge: number;
  } {
    return {
      ...this.getCookieOptions(),
      maxAge: 0
    };
  }

  /**
   * Create HMAC signature of payload
   */
  private sign(payload: string): string {
    const hmac = createHmac('sha256', this.config.secret);
    hmac.update(payload);
    return hmac.digest('base64url');
  }

  /**
   * Timing-safe string comparison
   */
  private timingSafeCompare(a: string, b: string): boolean {
    try {
      const bufA = Buffer.from(a);
      const bufB = Buffer.from(b);

      if (bufA.length !== bufB.length) {
        // Compare with itself to maintain constant time
        timingSafeEqual(bufA, bufA);
        return false;
      }

      return timingSafeEqual(bufA, bufB);
    } catch {
      return false;
    }
  }

  /**
   * Base64URL encode a string
   */
  private base64UrlEncode(str: string): string {
    return Buffer.from(str, 'utf-8').toString('base64url');
  }

  /**
   * Base64URL decode a string
   */
  private base64UrlDecode(str: string): string {
    return Buffer.from(str, 'base64url').toString('utf-8');
  }
}

/**
 * Create session config from environment variables
 */
export function createSessionConfig(env: {
  AUTH_SESSION_SECRET?: string;
  NODE_ENV?: string;
}): SessionConfig {
  const secret = env.AUTH_SESSION_SECRET;

  if (!secret || secret.length < 32) {
    throw new Error(
      'AUTH_SESSION_SECRET environment variable is required and must be at least 32 characters'
    );
  }

  const isProduction = env.NODE_ENV === 'production';

  return {
    secret,
    cookieName: 'beetus_session',
    maxAge: DEFAULT_MAX_AGE,
    secure: isProduction
  };
}

/**
 * Singleton instance factory
 */
let sessionServiceInstance: SessionService | null = null;

export function getSessionService(config: SessionConfig): SessionService {
  if (!sessionServiceInstance) {
    sessionServiceInstance = new SessionService(config);
  }
  return sessionServiceInstance;
}
