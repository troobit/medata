/**
 * Workstream D: CSV Parsing Utilities
 * Branch: dev-4
 *
 * Low-level CSV parsing utilities.
 */

/**
 * Parse CSV text into an array of objects
 * Handles quoted fields, escaped quotes, and various line endings
 *
 * @param csvText - Raw CSV text
 * @returns Array of objects with column names as keys
 */
export function parseCSVText(csvText: string): Record<string, string>[] {
  const lines = csvText.split(/\r?\n/);
  const result: Record<string, string>[] = [];

  if (lines.length === 0) return result;

  // Find the header line (skip empty lines at the start)
  let headerIndex = 0;
  while (headerIndex < lines.length && lines[headerIndex].trim() === '') {
    headerIndex++;
  }

  if (headerIndex >= lines.length) return result;

  const headers = parseCSVLine(lines[headerIndex]);
  if (headers.length === 0) return result;

  // Parse data rows
  for (let i = headerIndex + 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line === '') continue;

    const values = parseCSVLine(line);
    const row: Record<string, string> = {};

    headers.forEach((header, index) => {
      row[header] = values[index] ?? '';
    });

    result.push(row);
  }

  return result;
}

/**
 * Parse a single CSV line into an array of values
 * Handles quoted fields and escaped quotes
 *
 * @param line - A single CSV line
 * @returns Array of field values
 */
export function parseCSVLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;
  let i = 0;

  while (i < line.length) {
    const char = line[i];

    if (inQuotes) {
      if (char === '"') {
        // Check for escaped quote
        if (i + 1 < line.length && line[i + 1] === '"') {
          current += '"';
          i += 2;
          continue;
        } else {
          inQuotes = false;
          i++;
          continue;
        }
      } else {
        current += char;
        i++;
      }
    } else {
      if (char === '"') {
        inQuotes = true;
        i++;
      } else if (char === ',') {
        result.push(current.trim());
        current = '';
        i++;
      } else {
        current += char;
        i++;
      }
    }
  }

  // Don't forget the last field
  result.push(current.trim());

  return result;
}

/**
 * Read a File as text
 *
 * @param file - File to read
 * @returns Promise resolving to file content as string
 */
export function readFileAsText(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(new Error('Failed to read file'));
    reader.readAsText(file);
  });
}

/**
 * Get column names from CSV text
 *
 * @param csvText - Raw CSV text
 * @returns Array of column names
 */
export function getCSVColumns(csvText: string): string[] {
  const lines = csvText.split(/\r?\n/);

  // Find first non-empty line
  for (const line of lines) {
    if (line.trim() !== '') {
      return parseCSVLine(line);
    }
  }

  return [];
}

/**
 * Detect if a column likely contains timestamps
 *
 * @param values - Sample values from the column
 * @returns True if the column appears to contain timestamps
 */
export function isTimestampColumn(values: string[]): boolean {
  const datePatterns = [
    /^\d{4}-\d{2}-\d{2}/, // ISO date prefix
    /^\d{2}-\d{2}-\d{4}/, // US/EU date prefix
    /T\d{2}:\d{2}/, // Time component
    /\d{2}:\d{2}:\d{2}/ // Time only
  ];

  const matches = values.filter((v) => datePatterns.some((p) => p.test(v)));
  return matches.length >= values.length * 0.8; // 80% threshold
}

/**
 * Detect if a column likely contains numeric BSL values
 *
 * @param values - Sample values from the column
 * @returns True if the column appears to contain BSL values
 */
export function isBSLColumn(values: string[]): boolean {
  const numericValues = values.map((v) => parseFloat(v)).filter((n) => !isNaN(n));

  if (numericValues.length < values.length * 0.8) return false;

  // Check if values are in reasonable BSL range
  // mmol/L: 2-30, mg/dL: 36-540
  const allInRange = numericValues.every(
    (n) => (n >= 2 && n <= 30) || (n >= 36 && n <= 540)
  );

  return allInRange;
}
