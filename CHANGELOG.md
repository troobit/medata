# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `Package.swift`, `MedataCore/Sources/{12 modules}/`, `HarnessCLI/main.swift` — Swift Package skeleton per design §2.1 (research tasks 1, 7); twelve module targets plus a macOS executable target and three test bundles, building with `swift build` and `swift test` on macOS 14 / iOS 17.
- `MedataCore/Sources/PortableContracts/Schemas/*.proto` — 27 canonical schemas covering every record that crosses a module boundary per design §4.3 and Decision 31; `generate.sh` regenerates the committed `Generated/*.pb.swift` sources via `protoc-gen-swift` (research tasks 2, 3).
- `MedataCore/Sources/PortableContracts/{Vec3,Mat4,Projection}.swift` — Swift-ergonomic types per design §3.1 with right-handed cross product, column-major Mat4 storage, `−Z`-forward projection, and bridges to/from the generated `Pb*` types (research task 5).
- `MedataCore/Sources/CaptureKit/SimdAdapter.swift` — `simd_float3` ↔ `Vec3` and `simd_float4x4` ↔ `Mat4` conversions, scoped to `CaptureKit` only per the design boundary rule.
- `MedataCore/Sources/CaptureKit/MetalContext.swift` — `@unchecked Sendable` shared device/queue/library context per design §3.1.1; falls back to an empty in-memory library so the lifecycle test runs on hosts without a bundled metallib (research tasks 6, 7).
- `MedataCore/Tests/PortableContractsTests/` — 21 round-trip and convention tests covering protobuf binary, deterministic protobuf-JSON, Vec3/Mat4 conventions, and the `Pb` ↔ Swift bridge (research tasks 2, 4).
- `MedataCore/Tests/CaptureKitTests/` — 5 tests covering simd interop and the MetalContext lifecycle (research tasks 4, 6); skip gracefully when no Metal device is available.
- `.swiftformat`, `.gitattributes` — Swift formatting config and Git LFS rules for fixture artefacts and the bundled segmenter package per task 1.
- `docs/agent-notes/swift-package.md` — agent context note describing the package topology, generated-protobuf naming, and build/test entry points.

### Changed
- `.gitignore` — added Swift / Xcode build artefact patterns (`.build/`, `.swiftpm/`, `DerivedData/`, `*.xcodeproj/xcuserdata/`, `Package.resolved`).
- `specs/research/tasks.md` — Foundation phase tasks 1–7 marked complete.

### Previously added
- `src/routes/capture/+page.svelte` — full capture page wiring: fetch `/api/recognition/status` on mount with skeleton loading state, conditional ManualEntryCTA/MockModeBanner rendering, 10MB client-side image size check, `handleSave()` wired to `POST /api/meals` with Blob Storage image upload (Req 6.4, 11.1, 11.3)

### Added
- `src/routes/capture/page.test.ts` — 7 tests for capture page status detection and conditional rendering: skeleton/loading state, ManualEntryCTA for unconfigured/error states, MockModeBanner for mock mode, recognition path for configured state (Task 22)

### Removed
- `@anthropic-ai/sdk` dependency — removed from `package.json` and `pnpm-lock.yaml` (D-MVR-013)
- `src/lib/services/claude-food-recognition.ts` — old Anthropic SDK-based service (replaced by `HttpRecognitionService`)
- `src/lib/services/food-recognition.ts` — old interface with `LabelContext`, `IFoodRecognitionService` (replaced by `recognition.ts`)
- `src/routes/api/ai/recognise/+server.ts` — old API route (replaced by `/api/recognition/analyse`)

### Changed
- `src/routes/capture/+page.svelte` — updated to call `/api/recognition/analyse` instead of `/api/ai/recognise`, removed label scanning references
- `src/lib/services/index.ts` — removed barrel exports for deleted `food-recognition` and `claude-food-recognition` modules
- Renamed route test files from `+page.test.ts` to `page.test.ts` to fix SvelteKit build compatibility

### Previously added
- `createRecognitionService()` factory in `src/lib/services/recognition.ts` — returns `MockRecognitionService` when `RECOGNITION_MOCK_MODE=true`, `HttpRecognitionService` otherwise
- `recognition.test.ts` — unit tests for `createRecognitionService()` factory (3 tests)
- `/api/recognition/status` endpoint (`src/routes/api/recognition/status/+server.ts`) — returns `{ configured, mockMode }` with fail-safe default on error
- `/api/recognition/status` tests — 5 tests covering configured/unconfigured/mock/error scenarios
- `/api/recognition/analyse` endpoint (`src/routes/api/recognition/analyse/+server.ts`) — POST handler with image size validation, base64→Blob conversion, `RecognitionError` → HTTP status mapping, Irish English error messages (Req 11.4)
- `/api/recognition/analyse` tests — 9 tests covering success, 503/504/422/413/429/502 error codes, and Irish English spelling validation
- `IRecognitionService` interface, `RecognitionError` class, and canonical types in `src/lib/services/recognition.ts` — provider-agnostic recognition layer (D-MVR-013, D-MVR-015)
- `MockModeBanner.svelte` component — amber banner indicating mock mode is active
- `ManualEntryCTA.svelte` component — call-to-action when recognition is not configured
- `CameraCapture.test.ts` — tests for stream cleanup, camera detection via `enumerateDevices`, and gallery upload parity
- Property-based tests for `sumMacros` using `fast-check` — validates macro sum identity, zero totals, and non-negativity invariants
- `MockRecognitionService` implementation (`src/lib/services/mock-recognition.ts`) — returns realistic fake food data with 500–1500ms simulated delay (Req 5.1–5.5)
- `mock-recognition.test.ts` — unit tests for `MockRecognitionService` covering schema, delay, notes prefix, and macro validity
- `MealEditor.svelte` — `mockMode` prop with `MockModeBanner` rendering, error toast with state retention on failed save (Req 5.5, 11.1)
- `src/routes/manual/+page.test.ts` — manual entry flow tests (Req 7.1–7.3)
- `src/routes/+page.test.ts` — logbook display, meal edit/delete tests (Req 8.1–8.5)
- `src/routes/presets/+page.test.ts` — preset save, apply, edit, delete tests (Req 9.1–9.4)
- HTTPS dev server via `@vitejs/plugin-basic-ssl` with LAN binding (`server.host: true`) for mobile camera access (Req 1.1, 1.2)
- Provider-agnostic environment variables: `RECOGNITION_BASE_URL`, `RECOGNITION_MODEL`, `RECOGNITION_API_KEY`, `RECOGNITION_MOCK_MODE`, `RECOGNITION_TIMEOUT_MS`
- Developer setup guide with Ollama, cloud model, and mock mode configuration options
- `HttpRecognitionService` implementation (`src/lib/services/http-recognition.ts`) — OpenAI-compatible `/v1/chat/completions` client with configurable timeout, optional auth, and AbortController support (Req 4.3, 11.2)
- `parseAnalysisResult()` function — validates and extracts `FoodAnalysisResult` from OpenAI-compat response envelopes, handles markdown-fenced JSON and pre-parsed objects
- `http-recognition.test.ts` — 23 unit tests covering `parseAnalysisResult` (JSON extraction, markdown fence stripping, schema validation, error codes) and `HttpRecognitionService` (isReady, auth headers, request shape, timeout, backend errors)

### Changed
- `CameraCapture.svelte` — replaced UA-string detection with `enumerateDevices()` feature detection; added `onDestroy`/`beforeNavigate` stream cleanup (Req 2.4, D-MVR-011, D-MVR-018); gallery-only mode when no camera detected
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
