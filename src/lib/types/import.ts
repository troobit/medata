/**
 * Workstream D: BSL Data Import Types
 * Owner: workstream-d/bsl-import branch
 *
 * This file defines types for importing BSL data from CSV files
 * and manual entry.
 * Implementations should be added to src/lib/services/import/
 */

import type { BSLUnit, PhysiologicalEvent } from './events';

/**
 * Supported CSV format types
 */
export type CSVFormatType = 'freestyle-libre' | 'dexcom' | 'generic';

/**
 * Column mapping for generic CSV import
 */
export interface CSVColumnMapping {
  timestampColumn: string;
  valueColumn: string;
  unitColumn?: string; // if unit varies per row
  deviceColumn?: string;
}

/**
 * Parsed row from CSV before conversion to event
 */
export interface ParsedCSVRow {
  timestamp: Date;
  value: number;
  unit: BSLUnit;
  device?: string;
  rawRow: Record<string, string>; // original CSV data
  lineNumber: number;
}

/**
 * Import validation result for a single row
 */
export interface RowValidationResult {
  row: ParsedCSVRow;
  isValid: boolean;
  errors: string[];
  warnings: string[];
}

/**
 * Duplicate detection result
 */
export interface DuplicateMatch {
  importRow: ParsedCSVRow;
  existingEvent: PhysiologicalEvent;
  matchType: 'exact' | 'near'; // exact = same timestamp+value, near = within 5 min
  timeDifferenceMs: number;
}

/**
 * Strategy for handling duplicates
 */
export type DuplicateStrategy = 'skip' | 'keep-existing' | 'keep-import' | 'keep-both';

/**
 * Import preview before committing
 */
export interface ImportPreview {
  format: CSVFormatType;
  totalRows: number;
  validRows: ParsedCSVRow[];
  invalidRows: RowValidationResult[];
  duplicates: DuplicateMatch[];
  dateRange: { start: Date; end: Date };
  sampleRows: ParsedCSVRow[]; // first 5 for UI preview
}

/**
 * Import result after committing
 */
export interface ImportResult {
  imported: number;
  skipped: number;
  failed: number;
  duplicatesHandled: number;
  events: PhysiologicalEvent[];
}

/**
 * Options for CSV import
 */
export interface CSVImportOptions {
  format?: CSVFormatType; // auto-detect if not provided
  columnMapping?: CSVColumnMapping; // for generic format
  defaultUnit?: BSLUnit;
  duplicateStrategy?: DuplicateStrategy;
  timezone?: string; // IANA timezone, e.g., 'Australia/Sydney'
}

/**
 * Interface for CSV import service
 * Implementations: CSVParser, LibreCSVParser, DexcomCSVParser, GenericCSVParser
 */
export interface IImportService {
  detectFormat(file: File): Promise<CSVFormatType>;
  parseCSV(file: File, options?: CSVImportOptions): Promise<ImportPreview>;
  validateRows(rows: ParsedCSVRow[]): RowValidationResult[];
  findDuplicates(rows: ParsedCSVRow[]): Promise<DuplicateMatch[]>;
  commitImport(preview: ImportPreview, duplicateStrategy: DuplicateStrategy): Promise<ImportResult>;
}

/**
 * Interface for export service
 */
export interface IExportService {
  exportToJSON(events: PhysiologicalEvent[]): Blob;
  exportToCSV(events: PhysiologicalEvent[]): Blob;
  generateBackup(): Promise<Blob>;
  restoreBackup(backup: Blob): Promise<ImportResult>;
}
