# CGM Graph Image Capture Services

Services for extracting BSL data from CGM app screenshots.

## Interface

Implements `ICGMImageService` from `$lib/types/cgm.ts`

## Files

- `CGMImageProcessor.ts` - Main processing orchestrator
- `LibreGraphParser.ts` - Freestyle Libre graph format parser
- `DexcomGraphParser.ts` - Dexcom graph format parser
- `LocalCurveExtractor.ts` - Curve tracing algorithms
- `CGMApiFactory.ts` - Factory for CGM API services
- `LibreLinkApiService.ts` - LibreLink API integration
- `DexcomShareApiService.ts` - Dexcom Share API integration

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
