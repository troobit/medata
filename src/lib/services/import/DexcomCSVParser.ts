/**
 * Workstream D: Dexcom Clarity CSV Parser
 * Branch: dev-4
 *
 * Parses Dexcom Clarity CSV export files.
 *
 * Sample format:
 * Index,Timestamp (YYYY-MM-DDThh:mm:ss),Event Type,Event Subtype,Glucose Value (mg/dL),...
 * 1,2026-01-15T08:30:00,EGV,,112,...
 */

import type { ParsedCSVRow, RowValidationResult } from '$lib/types';
import type { BSLUnit } from '$lib/types';
import { parseCSVText, readFileAsText } from '$lib/utils/csvHelpers';
import { parseISODate } from '$lib/utils/dateNormalization';

/**
 * Dexcom CSV column names
 */
const DEXCOM_COLUMNS = {
  TIMESTAMP: ['Timestamp (YYYY-MM-DDThh:mm:ss)', 'Timestamp', 'Time'],
  GLUCOSE_MGDL: ['Glucose Value (mg/dL)', 'Glucose Value', 'EGV Value'],
  GLUCOSE_MMOL: ['Glucose Value (mmol/L)'],
  EVENT_TYPE: ['Event Type'],
  TRANSMITTER: ['Transmitter ID', 'Transmitter']
};

/**
 * Dexcom event types that indicate glucose readings
 * EGV = Estimated Glucose Value (continuous readings)
 * Calibration = Calibration readings
 */
const GLUCOSE_EVENT_TYPES = ['EGV', 'egv', 'Calibration', 'calibration'];

/**
 * Parse a Dexcom Clarity CSV export file
 *
 * @param file - CSV file to parse
 * @returns Parsed rows
 */
export async function parseDexcomCSV(file: File): Promise<{
  rows: ParsedCSVRow[];
  device: string | undefined;
  detectedUnit: BSLUnit;
}> {
  const text = await readFileAsText(file);
  const data = parseCSVText(text);

  if (data.length === 0) {
    return { rows: [], device: undefined, detectedUnit: 'mg/dL' };
  }

  // Find the relevant columns
  const firstRow = data[0];
  const columns = Object.keys(firstRow);

  const timestampCol = findColumn(columns, DEXCOM_COLUMNS.TIMESTAMP);
  const glucoseMgdlCol = findColumn(columns, DEXCOM_COLUMNS.GLUCOSE_MGDL);
  const glucoseMmolCol = findColumn(columns, DEXCOM_COLUMNS.GLUCOSE_MMOL);
  const eventTypeCol = findColumn(columns, DEXCOM_COLUMNS.EVENT_TYPE);
  const transmitterCol = findColumn(columns, DEXCOM_COLUMNS.TRANSMITTER);

  // Dexcom primarily uses mg/dL
  const glucoseCol = glucoseMmolCol || glucoseMgdlCol;
  const detectedUnit: BSLUnit = glucoseMmolCol ? 'mmol/L' : 'mg/dL';

  if (!timestampCol || !glucoseCol) {
    throw new Error(
      'Could not find required columns in Dexcom CSV. Expected: Timestamp, Glucose Value'
    );
  }

  // Get device info from transmitter column
  const device = transmitterCol ? `Dexcom ${data[0][transmitterCol] || ''}`.trim() : 'Dexcom CGM';

  const rows: ParsedCSVRow[] = [];

  for (let i = 0; i < data.length; i++) {
    const row = data[i];

    // Filter by event type if column exists
    if (eventTypeCol) {
      const eventType = row[eventTypeCol];
      if (!GLUCOSE_EVENT_TYPES.includes(eventType)) {
        continue;
      }
    }

    const timestampStr = row[timestampCol];
    const glucoseStr = row[glucoseCol];

    // Skip empty values or "Low"/"High" strings
    if (!timestampStr || !glucoseStr) continue;
    if (glucoseStr.toLowerCase() === 'low' || glucoseStr.toLowerCase() === 'high') continue;

    const timestamp = parseISODate(timestampStr);
    const value = parseFloat(glucoseStr);

    if (!timestamp || isNaN(value)) continue;

    // Convert to mmol/L if in mg/dL
    const normalizedValue = detectedUnit === 'mg/dL' ? value / 18.0182 : value;

    rows.push({
      timestamp,
      value: normalizedValue,
      unit: 'mmol/L', // Always store in mmol/L
      device,
      rawRow: row,
      lineNumber: i + 2 // +1 for header, +1 for 1-based indexing
    });
  }

  return { rows, device, detectedUnit };
}

/**
 * Validate parsed Dexcom CSV rows
 *
 * @param rows - Parsed rows to validate
 * @returns Validation results
 */
export function validateDexcomRows(rows: ParsedCSVRow[]): RowValidationResult[] {
  return rows.map((row) => {
    const errors: string[] = [];
    const warnings: string[] = [];

    // Validate timestamp
    if (!row.timestamp || isNaN(row.timestamp.getTime())) {
      errors.push('Invalid timestamp');
    } else {
      if (row.timestamp > new Date()) {
        warnings.push('Timestamp is in the future');
      }
      const yearAgo = new Date();
      yearAgo.setFullYear(yearAgo.getFullYear() - 5);
      if (row.timestamp < yearAgo) {
        warnings.push('Timestamp is more than 5 years old');
      }
    }

    // Validate BSL value (in mmol/L)
    if (isNaN(row.value)) {
      errors.push('Invalid glucose value');
    } else if (row.value < 2 || row.value > 30) {
      if (row.value < 1 || row.value > 35) {
        errors.push(`Glucose value ${row.value.toFixed(1)} out of valid range (2-30 mmol/L)`);
      } else {
        warnings.push(`Glucose value ${row.value.toFixed(1)} is outside typical range`);
      }
    }

    return {
      row,
      isValid: errors.length === 0,
      errors,
      warnings
    };
  });
}

/**
 * Detect if a file is a Dexcom Clarity CSV export
 *
 * @param file - File to check
 * @returns True if the file appears to be a Dexcom export
 */
export async function isDexcomCSV(file: File): Promise<boolean> {
  try {
    const text = await readFileAsText(file);
    const firstLines = text.split(/\r?\n/).slice(0, 5).join('\n').toLowerCase();

    // Check for Dexcom-specific indicators
    const indicators = ['dexcom', 'egv', 'transmitter', 'glucose value (mg/dl)'];

    return indicators.some((ind) => firstLines.includes(ind));
  } catch {
    return false;
  }
}

/**
 * Find a column name from a list of possible names
 */
function findColumn(columns: string[], possibleNames: string[]): string | undefined {
  for (const name of possibleNames) {
    const found = columns.find((c) => c.toLowerCase().includes(name.toLowerCase()));
    if (found) return found;
  }
  return undefined;
}
