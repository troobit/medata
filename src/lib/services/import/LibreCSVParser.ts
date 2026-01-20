/**
 * Workstream D: Freestyle Libre CSV Parser
 * Branch: dev-4
 *
 * Parses Freestyle Libre CSV export files.
 *
 * Sample format:
 * Device,Serial Number,Device Timestamp,Record Type,Historic Glucose mmol/L,...
 * FreeStyle Libre 3,ABC123,01-15-2026 08:30,0,5.6,...
 */

import type { ParsedCSVRow, RowValidationResult } from '$lib/types';
import type { BSLUnit } from '$lib/types';
import { parseCSVText, readFileAsText } from '$lib/utils/csvHelpers';
import { parseLibreDate } from '$lib/utils/dateNormalization';

/**
 * Libre CSV column names (may vary by region/version)
 */
const LIBRE_COLUMNS = {
  TIMESTAMP: ['Device Timestamp', 'Timestamp', 'Time'],
  GLUCOSE_MMOL: ['Historic Glucose mmol/L', 'Glucose Value (mmol/L)', 'Scan Glucose mmol/L'],
  GLUCOSE_MGDL: ['Historic Glucose mg/dL', 'Glucose Value (mg/dL)', 'Scan Glucose mg/dL'],
  RECORD_TYPE: ['Record Type'],
  DEVICE: ['Device', 'Device Type']
};

/**
 * Libre record types that indicate glucose readings
 * 0 = Historic glucose (auto-scanned)
 * 1 = Scan glucose (manual scan)
 * 6 = Sensor started
 */
const GLUCOSE_RECORD_TYPES = ['0', '1'];

/**
 * Parse a Freestyle Libre CSV export file
 *
 * @param file - CSV file to parse
 * @returns Parsed rows
 */
export async function parseLibreCSV(file: File): Promise<{
  rows: ParsedCSVRow[];
  device: string | undefined;
  detectedUnit: BSLUnit;
}> {
  const text = await readFileAsText(file);
  const data = parseCSVText(text);

  if (data.length === 0) {
    return { rows: [], device: undefined, detectedUnit: 'mmol/L' };
  }

  // Find the relevant columns
  const firstRow = data[0];
  const columns = Object.keys(firstRow);

  const timestampCol = findColumn(columns, LIBRE_COLUMNS.TIMESTAMP);
  const glucoseMmolCol = findColumn(columns, LIBRE_COLUMNS.GLUCOSE_MMOL);
  const glucoseMgdlCol = findColumn(columns, LIBRE_COLUMNS.GLUCOSE_MGDL);
  const recordTypeCol = findColumn(columns, LIBRE_COLUMNS.RECORD_TYPE);
  const deviceCol = findColumn(columns, LIBRE_COLUMNS.DEVICE);

  // Determine which unit is available
  const glucoseCol = glucoseMmolCol || glucoseMgdlCol;
  const detectedUnit: BSLUnit = glucoseMmolCol ? 'mmol/L' : 'mg/dL';

  if (!timestampCol || !glucoseCol) {
    throw new Error(
      'Could not find required columns in Libre CSV. Expected: Device Timestamp, Historic Glucose'
    );
  }

  // Get device name from first row with data
  const device = deviceCol ? data[0][deviceCol] : undefined;

  const rows: ParsedCSVRow[] = [];

  for (let i = 0; i < data.length; i++) {
    const row = data[i];

    // Skip non-glucose records if record type column exists
    if (recordTypeCol) {
      const recordType = row[recordTypeCol];
      if (!GLUCOSE_RECORD_TYPES.includes(recordType)) {
        continue;
      }
    }

    const timestampStr = row[timestampCol];
    const glucoseStr = row[glucoseCol];

    // Skip empty values
    if (!timestampStr || !glucoseStr) continue;

    const timestamp = parseLibreDate(timestampStr, true); // Libre uses US format
    const value = parseFloat(glucoseStr);

    if (!timestamp || isNaN(value)) continue;

    // Convert mg/dL to mmol/L if needed
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
 * Validate parsed Libre CSV rows
 *
 * @param rows - Parsed rows to validate
 * @returns Validation results
 */
export function validateLibreRows(rows: ParsedCSVRow[]): RowValidationResult[] {
  return rows.map((row) => {
    const errors: string[] = [];
    const warnings: string[] = [];

    // Validate timestamp
    if (!row.timestamp || isNaN(row.timestamp.getTime())) {
      errors.push('Invalid timestamp');
    } else {
      // Check for future dates
      if (row.timestamp > new Date()) {
        warnings.push('Timestamp is in the future');
      }
      // Check for very old dates
      const yearAgo = new Date();
      yearAgo.setFullYear(yearAgo.getFullYear() - 5);
      if (row.timestamp < yearAgo) {
        warnings.push('Timestamp is more than 5 years old');
      }
    }

    // Validate BSL value
    if (isNaN(row.value)) {
      errors.push('Invalid glucose value');
    } else if (row.value < 2 || row.value > 30) {
      // mmol/L range: 2-30
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
 * Detect if a file is a Freestyle Libre CSV export
 *
 * @param file - File to check
 * @returns True if the file appears to be a Libre export
 */
export async function isLibreCSV(file: File): Promise<boolean> {
  try {
    const text = await readFileAsText(file);
    const firstLines = text.split(/\r?\n/).slice(0, 5).join('\n').toLowerCase();

    // Check for Libre-specific indicators
    const indicators = [
      'freestyle libre',
      'libre',
      'historic glucose',
      'scan glucose',
      'device timestamp'
    ];

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
