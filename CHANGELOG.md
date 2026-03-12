# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `IRecognitionService` interface, `RecognitionError` class, and canonical types in `src/lib/services/recognition.ts` — provider-agnostic recognition layer (D-MVR-013, D-MVR-015)
- `MockModeBanner.svelte` component — amber banner indicating mock mode is active
- `ManualEntryCTA.svelte` component — call-to-action when recognition is not configured
- `CameraCapture.test.ts` — tests for stream cleanup, camera detection via `enumerateDevices`, and gallery upload parity (3 tests intentionally failing until Task 19 implements `enumerateDevices`)
- HTTPS dev server via `@vitejs/plugin-basic-ssl` with LAN binding (`server.host: true`) for mobile camera access (Req 1.1, 1.2)
- Provider-agnostic environment variables: `RECOGNITION_BASE_URL`, `RECOGNITION_MODEL`, `RECOGNITION_API_KEY`, `RECOGNITION_MOCK_MODE`, `RECOGNITION_TIMEOUT_MS`
- Developer setup guide with Ollama, cloud model, and mock mode configuration options

### Changed
- `RecognisedFoodItem` no longer extends with `quantity` and `unit` fields (D-MVR-017)
- `FoodRecognitionResult` no longer includes `totalMacros`, `provider`, or `processingTimeMs` fields
- `MealDataSource` type removes `label_scan` value — label scanning deferred (D-MVR-017)
- `RecognisedFoodItemSchema` and `MealDataSourceSchema` updated to match type changes
- `/api/ai/recognise` endpoint response simplified to return only `items` and `confidence`
- `FoodRecognitionResult.svelte` computes totals locally instead of receiving from API
- Dev server now serves HTTPS-only at `https://localhost:5173` (D-MVR-010)

### Removed
- `ANTHROPIC_API_KEY` from `.env.example` — replaced by `RECOGNITION_API_KEY`
- `label_scan` source type from `MealDataSource`, schemas, and UI components
- `quantity`/`unit` display from `FoodRecognitionResult.svelte`
