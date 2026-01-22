/**
 * Workstream D: Date Normalization Utilities
 * Branch: dev-4
 *
 * Handles parsing and normalizing dates from various CSV formats.
 */

/**
 * Common date formats found in CGM CSV exports
 */
export const DATE_FORMATS = {
  // Freestyle Libre: "01-15-2026 08:30" (MM-DD-YYYY HH:mm)
  LIBRE_US: /^(\d{2})-(\d{2})-(\d{4})\s+(\d{2}):(\d{2})$/,
  // Freestyle Libre EU: "15-01-2026 08:30" (DD-MM-YYYY HH:mm)
  LIBRE_EU: /^(\d{2})-(\d{2})-(\d{4})\s+(\d{2}):(\d{2})$/,
  // ISO 8601: "2026-01-15T08:30:00"
  ISO: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/,
  // Dexcom: "2026-01-15 08:30:00" (YYYY-MM-DD HH:mm:ss)
  DEXCOM: /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/
} as const;

/**
 * Parse a Freestyle Libre date string
 * Format: "MM-DD-YYYY HH:mm" or "DD-MM-YYYY HH:mm"
 *
 * @param dateStr - The date string to parse
 * @param usFormat - Whether to use US format (MM-DD-YYYY) or EU format (DD-MM-YYYY)
 * @returns Parsed Date or null if invalid
 */
export function parseLibreDate(dateStr: string, usFormat: boolean = true): Date | null {
  const match = dateStr.match(DATE_FORMATS.LIBRE_US);
  if (!match) return null;

  const [, first, second, year, hour, minute] = match;

  const month = usFormat ? parseInt(first, 10) - 1 : parseInt(second, 10) - 1;
  const day = usFormat ? parseInt(second, 10) : parseInt(first, 10);

  const date = new Date(parseInt(year, 10), month, day, parseInt(hour, 10), parseInt(minute, 10));

  // Validate the date is reasonable
  if (isNaN(date.getTime())) return null;
  if (date.getFullYear() < 2000 || date.getFullYear() > 2100) return null;

  return date;
}

/**
 * Parse an ISO 8601 date string
 * Format: "2026-01-15T08:30:00" or "2026-01-15T08:30:00Z"
 *
 * @param dateStr - The date string to parse
 * @returns Parsed Date or null if invalid
 */
export function parseISODate(dateStr: string): Date | null {
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return null;
  if (date.getFullYear() < 2000 || date.getFullYear() > 2100) return null;
  return date;
}

/**
 * Parse a Dexcom date string
 * Format: "2026-01-15 08:30:00"
 *
 * @param dateStr - The date string to parse
 * @returns Parsed Date or null if invalid
 */
export function parseDexcomDate(dateStr: string): Date | null {
  // Dexcom uses space instead of T, so normalize it
  const normalized = dateStr.replace(' ', 'T');
  return parseISODate(normalized);
}

/**
 * Detect the date format from a sample date string
 *
 * @param dateStr - Sample date string
 * @returns Detected format name or null
 */
export function detectDateFormat(dateStr: string): keyof typeof DATE_FORMATS | null {
  if (DATE_FORMATS.ISO.test(dateStr)) return 'ISO';
  if (DATE_FORMATS.DEXCOM.test(dateStr)) return 'DEXCOM';
  if (DATE_FORMATS.LIBRE_US.test(dateStr)) return 'LIBRE_US';
  return null;
}

/**
 * Parse a date string using auto-detection
 *
 * @param dateStr - The date string to parse
 * @param preferUSFormat - For ambiguous formats, prefer US (MM-DD) over EU (DD-MM)
 * @returns Parsed Date or null if invalid
 */
export function parseDate(dateStr: string, preferUSFormat: boolean = true): Date | null {
  if (!dateStr || typeof dateStr !== 'string') return null;

  const trimmed = dateStr.trim();

  // Try ISO format first (most reliable)
  if (DATE_FORMATS.ISO.test(trimmed)) {
    return parseISODate(trimmed);
  }

  // Try Dexcom format
  if (DATE_FORMATS.DEXCOM.test(trimmed)) {
    return parseDexcomDate(trimmed);
  }

  // Try Libre format
  if (DATE_FORMATS.LIBRE_US.test(trimmed)) {
    return parseLibreDate(trimmed, preferUSFormat);
  }

  // Fallback: try native Date parsing
  const fallback = new Date(trimmed);
  if (!isNaN(fallback.getTime())) {
    return fallback;
  }

  return null;
}

/**
 * Format a Date to ISO string for display
 */
export function formatDateForDisplay(date: Date): string {
  return date.toISOString().replace('T', ' ').slice(0, 19);
}

/**
 * Format a Date to local date/time string
 */
export function formatDateLocal(date: Date): string {
  return date.toLocaleString();
}
