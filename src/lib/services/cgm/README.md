# Workstream B: CGM Graph Image Capture Services

**Branch**: `workstream-b/cgm-capture`

This directory contains services for extracting BSL data from CGM app screenshots.

## Interface

Implement `ICGMImageService` from `$lib/types/cgm.ts`

## Files to create

- `CGMImageProcessor.ts` - Main processing orchestrator
- `LibreGraphParser.ts` - Freestyle Libre graph format parser
- `DexcomGraphParser.ts` - Dexcom graph format parser
- `CurveExtractor.ts` - Curve tracing algorithms
- `AxisDetector.ts` - OCR and axis range detection

## Supported Formats

| App             | Graph Style        | Time Range       |
| --------------- | ------------------ | ---------------- |
| Freestyle Libre | Yellow line, white | 8h, 12h, 24h     |
| Dexcom G6/G7    | Blue line, dark bg | 3h, 6h, 12h, 24h |

## Usage

```typescript
import { CGMImageProcessor } from '$lib/services/cgm';

const processor = new CGMImageProcessor();
const result = await processor.extractFromImage(screenshotBlob);
```
