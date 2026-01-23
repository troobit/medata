# Local Food Volume Estimation Services

Browser-local food volume estimation services.
No cloud API calls - all processing happens on device.

## Interface

Implements `IVolumeEstimationService` from `$lib/types/local-estimation.ts`

## Files

- `ReferenceDetector.ts` - Credit card/coin detection for scale
- `VolumeCalculator.ts` - Volume estimation from 2D regions
- `FoodDensityLookup.ts` - USDA FNDDS food density database
- `EstimationEngine.ts` - Orchestrates full estimation pipeline
- `CalibrationStore.ts` - Stores learned calibration from user corrections

## Reference Objects

| Object      | Dimensions (mm) |
| ----------- | --------------- |
| Credit Card | 85.6 × 53.98    |
| AU $1 Coin  | 25 diameter     |
| AU 50c Coin | 31.65 diameter  |

## Usage

```typescript
import { EstimationEngine } from '$lib/services/local-estimation';

const engine = new EstimationEngine();
const result = await engine.estimateFromImage(imageBlob, foodType);
```
