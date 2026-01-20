/**
 * Workstream D: Export Service
 * Branch: dev-4
 *
 * Handles exporting data to JSON and CSV formats.
 * Implements IExportService interface.
 */

import type { PhysiologicalEvent, IExportService, ImportResult } from '$lib/types';
import { getEventRepository } from '$lib/repositories';

/**
 * Export Service
 *
 * Handles exporting and backing up physiological event data.
 */
export class ExportService implements IExportService {
  /**
   * Export events to JSON format
   *
   * @param events - Events to export
   * @returns Blob containing JSON data
   */
  exportToJSON(events: PhysiologicalEvent[]): Blob {
    const data = {
      version: '1.0',
      exportedAt: new Date().toISOString(),
      count: events.length,
      events: events.map((e) => ({
        ...e,
        timestamp: new Date(e.timestamp).toISOString(),
        createdAt: new Date(e.createdAt).toISOString(),
        updatedAt: new Date(e.updatedAt).toISOString()
      }))
    };

    const json = JSON.stringify(data, null, 2);
    return new Blob([json], { type: 'application/json' });
  }

  /**
   * Export events to CSV format
   *
   * @param events - Events to export
   * @returns Blob containing CSV data
   */
  exportToCSV(events: PhysiologicalEvent[]): Blob {
    // CSV header
    const headers = [
      'id',
      'timestamp',
      'eventType',
      'value',
      'unit',
      'source',
      'device',
      'isFingerPrick',
      'insulinType',
      'carbs',
      'protein',
      'fat',
      'calories',
      'description',
      'createdAt',
      'updatedAt'
    ];

    // Build CSV rows
    const rows = events.map((event) => {
      const meta = event.metadata || {};
      return [
        event.id,
        new Date(event.timestamp).toISOString(),
        event.eventType,
        event.value,
        meta.unit || '',
        meta.source || '',
        meta.device || '',
        meta.isFingerPrick ?? '',
        meta.type || '', // insulin type
        meta.carbs || '',
        meta.protein || '',
        meta.fat || '',
        meta.calories || '',
        String(meta.description || '').replace(/"/g, '""'), // Escape quotes
        new Date(event.createdAt).toISOString(),
        new Date(event.updatedAt).toISOString()
      ]
        .map((val) => {
          // Quote fields that contain commas, quotes, or newlines
          const str = String(val);
          if (str.includes(',') || str.includes('"') || str.includes('\n')) {
            return `"${str}"`;
          }
          return str;
        })
        .join(',');
    });

    const csv = [headers.join(','), ...rows].join('\n');
    return new Blob([csv], { type: 'text/csv' });
  }

  /**
   * Generate a full backup of all events
   *
   * @returns Blob containing full backup in JSON format
   */
  async generateBackup(): Promise<Blob> {
    const repository = getEventRepository();
    const events = await repository.exportAll();

    const backup = {
      version: '1.0',
      type: 'backup',
      createdAt: new Date().toISOString(),
      count: events.length,
      events: events.map((e) => ({
        ...e,
        timestamp: new Date(e.timestamp).toISOString(),
        createdAt: new Date(e.createdAt).toISOString(),
        updatedAt: new Date(e.updatedAt).toISOString()
      }))
    };

    const json = JSON.stringify(backup, null, 2);
    return new Blob([json], { type: 'application/json' });
  }

  /**
   * Restore data from a backup file
   *
   * @param backup - Blob containing backup data
   * @returns Import result with statistics
   */
  async restoreBackup(backup: Blob): Promise<ImportResult> {
    const text = await backup.text();
    let data: {
      version: string;
      type?: string;
      events: Array<{
        id: string;
        timestamp: string;
        eventType: string;
        value: number;
        metadata: Record<string, unknown>;
        createdAt: string;
        updatedAt: string;
        synced?: boolean;
      }>;
    };

    try {
      data = JSON.parse(text);
    } catch {
      throw new Error('Invalid backup file format');
    }

    if (!data.events || !Array.isArray(data.events)) {
      throw new Error('Invalid backup file: missing events array');
    }

    const repository = getEventRepository();

    // Convert dates back to Date objects
    const events: PhysiologicalEvent[] = data.events.map((e) => ({
      id: e.id,
      timestamp: new Date(e.timestamp),
      eventType: e.eventType as PhysiologicalEvent['eventType'],
      value: e.value,
      metadata: e.metadata,
      createdAt: new Date(e.createdAt),
      updatedAt: new Date(e.updatedAt),
      synced: e.synced
    }));

    // Import all events
    let imported = 0;
    let failed = 0;

    for (const event of events) {
      try {
        await repository.create({
          timestamp: event.timestamp,
          eventType: event.eventType,
          value: event.value,
          metadata: event.metadata
        });
        imported++;
      } catch {
        failed++;
      }
    }

    return {
      imported,
      skipped: 0,
      failed,
      duplicatesHandled: 0,
      events: []
    };
  }
}

/**
 * Get a singleton ExportService instance
 */
let exportServiceInstance: ExportService | null = null;

export function getExportService(): ExportService {
  if (!exportServiceInstance) {
    exportServiceInstance = new ExportService();
  }
  return exportServiceInstance;
}

/**
 * Utility: Download a blob as a file
 *
 * @param blob - Data to download
 * @param filename - Suggested filename
 */
export function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * Utility: Generate a filename with timestamp
 *
 * @param prefix - Filename prefix
 * @param extension - File extension
 * @returns Filename with timestamp
 */
export function generateFilename(prefix: string, extension: string): string {
  const date = new Date().toISOString().slice(0, 10);
  return `${prefix}-${date}.${extension}`;
}
