# Workstream D: BSL Data Import Services

**Branch**: `workstream-d/bsl-import`

This directory contains services for importing BSL data from CSV files.

## Interfaces

Implement `IImportService` and `IExportService` from `$lib/types/import.ts`

## Files to create

- `CSVParser.ts` - Base CSV parsing utilities
- `LibreCSVParser.ts` - Freestyle Libre export format parser
- `DexcomCSVParser.ts` - Dexcom Clarity export format parser
- `GenericCSVParser.ts` - Generic CSV with column mapping
- `DuplicateDetector.ts` - Duplicate event detection

## Supported CSV Formats

### Freestyle Libre

```csv
Device,Serial Number,Device Timestamp,Record Type,Historic Glucose mmol/L
FreeStyle Libre 3,ABC123,01-15-2026 08:30,0,5.6
```

### Dexcom Clarity

```csv
Index,Timestamp (YYYY-MM-DDThh:mm:ss),Event Type,Glucose Value (mg/dL)
1,2026-01-15T08:30:00,EGV,112
```

## Usage

```typescript
import { CSVParser } from '$lib/services/import';

const parser = new CSVParser();
const preview = await parser.parseCSV(file);
const result = await parser.commitImport(preview, 'skip');
```
