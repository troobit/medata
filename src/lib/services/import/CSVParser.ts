/**
 * Workstream D: CSV Import Service
 * Branch: dev-4
 *
 * Main orchestrator for CSV import functionality.
 * Implements IImportService interface.
 */

import type {
  CSVFormatType,
  CSVImportOptions,
  ImportPreview,
  ImportResult,
  ParsedCSVRow,
  RowValidationResult,
  DuplicateMatch,
  DuplicateStrategy,
  IImportService,
  PhysiologicalEvent,
  BSLMetadata
} from '$lib/types';
import { getEventRepository } from '$lib/repositories';
import { parseLibreCSV, isLibreCSV } from './LibreCSVParser';
import { parseDexcomCSV, isDexcomCSV } from './DexcomCSVParser';
import { parseGenericCSV, validateGenericRows, suggestColumnMapping } from './GenericCSVParser';
import { findDuplicates, filterRowsByStrategy } from './DuplicateDetector';

/**
 * CSV Import Service
 *
 * Handles parsing, validation, and importing of BSL data from CSV files.
 */
export class CSVParser implements IImportService {
  /**
   * Detect the format of a CSV file
   *
   * @param file - CSV file to analyse
   * @returns Detected format type
   */
  async detectFormat(file: File): Promise<CSVFormatType> {
    // Check for Libre format first (most common)
    if (await isLibreCSV(file)) {
      return 'freestyle-libre';
    }

    // Check for Dexcom format
    if (await isDexcomCSV(file)) {
      return 'dexcom';
    }

    // Default to generic
    return 'generic';
  }

  /**
   * Parse a CSV file and prepare for import
   *
   * @param file - CSV file to parse
   * @param options - Import options
   * @returns Import preview with parsed data
   */
  async parseCSV(file: File, options?: CSVImportOptions): Promise<ImportPreview> {
    // Detect or use provided format
    const format = options?.format ?? (await this.detectFormat(file));

    // Parse based on format
    let rows: ParsedCSVRow[];
    let device: string | undefined;

    switch (format) {
      case 'freestyle-libre': {
        const result = await parseLibreCSV(file);
        rows = result.rows;
        device = result.device;
        break;
      }
      case 'dexcom': {
        const result = await parseDexcomCSV(file);
        rows = result.rows;
        device = result.device;
        break;
      }
      case 'generic': {
        // For generic format, we need column mapping
        const mapping = options?.columnMapping ?? (await suggestColumnMapping(file));
        if (!mapping) {
          throw new Error('Could not auto-detect columns. Please provide column mapping.');
        }
        const result = await parseGenericCSV(file, mapping, options?.defaultUnit);
        rows = result.rows;
        device = result.device;
        break;
      }
    }

    // Apply device to all rows if detected
    if (device) {
      rows = rows.map((r) => ({ ...r, device: r.device ?? device }));
    }

    // Validate all rows
    const validationResults = this.validateRows(rows);
    const validRows = validationResults.filter((r) => r.isValid).map((r) => r.row);
    const invalidRows = validationResults.filter((r) => !r.isValid);

    // Find duplicates
    const duplicates = await this.findDuplicates(validRows);

    // Calculate date range
    const timestamps = validRows.map((r) => r.timestamp.getTime());
    const dateRange = {
      start: new Date(Math.min(...timestamps)),
      end: new Date(Math.max(...timestamps))
    };

    // Get sample rows for preview
    const sampleRows = validRows.slice(0, 5);

    return {
      format,
      totalRows: rows.length,
      validRows,
      invalidRows,
      duplicates,
      dateRange,
      sampleRows
    };
  }

  /**
   * Validate parsed CSV rows
   *
   * @param rows - Rows to validate
   * @returns Validation results
   */
  validateRows(rows: ParsedCSVRow[]): RowValidationResult[] {
    // Use the generic validator (works for all formats after parsing)
    return validateGenericRows(rows);
  }

  /**
   * Find duplicates between import rows and existing data
   *
   * @param rows - Parsed rows to check
   * @returns Duplicate matches
   */
  async findDuplicates(rows: ParsedCSVRow[]): Promise<DuplicateMatch[]> {
    return findDuplicates(rows);
  }

  /**
   * Commit the import to the database
   *
   * @param preview - Import preview from parseCSV
   * @param duplicateStrategy - How to handle duplicates
   * @returns Import result with statistics
   */
  async commitImport(
    preview: ImportPreview,
    duplicateStrategy: DuplicateStrategy
  ): Promise<ImportResult> {
    const repository = getEventRepository();

    // Filter rows based on duplicate strategy
    const { toImport, toSkip, toDelete } = filterRowsByStrategy(
      preview.validRows,
      preview.duplicates,
      duplicateStrategy
    );

    // Delete existing events if strategy requires
    for (const event of toDelete) {
      await repository.delete(event.id);
    }

    // Convert rows to events and import
    const events: PhysiologicalEvent[] = [];

    for (const row of toImport) {
      const metadata: BSLMetadata = {
        unit: row.unit,
        source: 'csv-import',
        device: row.device
      };

      const event = await repository.create({
        timestamp: row.timestamp,
        eventType: 'bsl',
        value: row.value,
        metadata
      });

      events.push(event);
    }

    return {
      imported: events.length,
      skipped: toSkip.length,
      failed: preview.invalidRows.length,
      duplicatesHandled: preview.duplicates.length,
      events
    };
  }
}

/**
 * Get a singleton CSVParser instance
 */
let csvParserInstance: CSVParser | null = null;

export function getCSVParser(): CSVParser {
  if (!csvParserInstance) {
    csvParserInstance = new CSVParser();
  }
  return csvParserInstance;
}
