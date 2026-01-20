/**
 * Workstream D: Generic CSV Parser
 * Branch: dev-4
 *
 * Parses generic CSV files with user-provided column mapping.
 */

import type { ParsedCSVRow, RowValidationResult, CSVColumnMapping } from '$lib/types';
import type { BSLUnit } from '$lib/types';
import { parseCSVText, readFileAsText, getCSVColumns } from '$lib/utils/csvHelpers';
import { parseDate } from '$lib/utils/dateNormalization';

/**
 * Parse a generic CSV file with column mapping
 *
 * @param file - CSV file to parse
 * @param mapping - Column mapping configuration
 * @param defaultUnit - Default unit if not in CSV
 * @returns Parsed rows
 */
export async function parseGenericCSV(
  file: File,
  mapping: CSVColumnMapping,
  defaultUnit: BSLUnit = 'mmol/L'
): Promise<{
  rows: ParsedCSVRow[];
  device: string | undefined;
  detectedUnit: BSLUnit;
}> {
  const text = await readFileAsText(file);
  const data = parseCSVText(text);

  if (data.length === 0) {
    return { rows: [], device: undefined, detectedUnit: defaultUnit };
  }

  const rows: ParsedCSVRow[] = [];

  for (let i = 0; i < data.length; i++) {
    const row = data[i];

    const timestampStr = row[mapping.timestampColumn];
    const valueStr = row[mapping.valueColumn];

    // Skip empty values
    if (!timestampStr || !valueStr) continue;

    const timestamp = parseDate(timestampStr);
    const value = parseFloat(valueStr);

    if (!timestamp || isNaN(value)) continue;

    // Get unit from row or use default
    let rowUnit: BSLUnit = defaultUnit;
    if (mapping.unitColumn && row[mapping.unitColumn]) {
      const unitStr = row[mapping.unitColumn].toLowerCase();
      if (unitStr.includes('mg')) {
        rowUnit = 'mg/dL';
      } else if (unitStr.includes('mmol')) {
        rowUnit = 'mmol/L';
      }
    }

    // Normalize to mmol/L
    const normalizedValue = rowUnit === 'mg/dL' ? value / 18.0182 : value;

    // Get device from row if column specified
    const device = mapping.deviceColumn ? row[mapping.deviceColumn] : undefined;

    rows.push({
      timestamp,
      value: normalizedValue,
      unit: 'mmol/L',
      device,
      rawRow: row,
      lineNumber: i + 2
    });
  }

  return { rows, device: undefined, detectedUnit: defaultUnit };
}

/**
 * Validate parsed generic CSV rows
 *
 * @param rows - Parsed rows to validate
 * @returns Validation results
 */
export function validateGenericRows(rows: ParsedCSVRow[]): RowValidationResult[] {
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
      const fiveYearsAgo = new Date();
      fiveYearsAgo.setFullYear(fiveYearsAgo.getFullYear() - 5);
      if (row.timestamp < fiveYearsAgo) {
        warnings.push('Timestamp is more than 5 years old');
      }
    }

    // Validate BSL value
    if (isNaN(row.value)) {
      errors.push('Invalid glucose value');
    } else if (row.value < 2 || row.value > 30) {
      if (row.value < 1 || row.value > 35) {
        errors.push(`Glucose value ${row.value.toFixed(1)} out of valid range`);
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
 * Auto-detect column mapping from CSV columns
 *
 * @param file - CSV file to analyze
 * @returns Suggested column mapping or null if unable to detect
 */
export async function suggestColumnMapping(file: File): Promise<CSVColumnMapping | null> {
  const text = await readFileAsText(file);
  const columns = getCSVColumns(text);

  if (columns.length === 0) return null;

  // Common timestamp column names
  const timestampPatterns = [
    'timestamp',
    'time',
    'date',
    'datetime',
    'device timestamp',
    'reading time'
  ];

  // Common value column names
  const valuePatterns = [
    'glucose',
    'value',
    'reading',
    'bg',
    'blood glucose',
    'bsl',
    'blood sugar'
  ];

  // Common unit column names
  const unitPatterns = ['unit', 'units'];

  // Common device column names
  const devicePatterns = ['device', 'meter', 'source'];

  const timestampColumn = findBestMatch(columns, timestampPatterns);
  const valueColumn = findBestMatch(columns, valuePatterns);
  const unitColumn = findBestMatch(columns, unitPatterns);
  const deviceColumn = findBestMatch(columns, devicePatterns);

  if (!timestampColumn || !valueColumn) {
    return null;
  }

  return {
    timestampColumn,
    valueColumn,
    unitColumn,
    deviceColumn
  };
}

/**
 * Get available columns from a CSV file
 *
 * @param file - CSV file to analyze
 * @returns Array of column names
 */
export async function getAvailableColumns(file: File): Promise<string[]> {
  const text = await readFileAsText(file);
  return getCSVColumns(text);
}

/**
 * Find the best matching column name from patterns
 */
function findBestMatch(columns: string[], patterns: string[]): string | undefined {
  for (const pattern of patterns) {
    const found = columns.find((c) => c.toLowerCase().includes(pattern.toLowerCase()));
    if (found) return found;
  }
  return undefined;
}
