---
references:
    - specs/mvp-refinement/requirements.md
    - specs/mvp-refinement/design.md
    - specs/mvp-refinement/decision_log.md
---
# MVP Refinement

## Foundation

- [x] 1. Update meal types: remove quantity/unit from AnalysedFoodItem, remove totalMacros/provider/processingTimeMs from FoodAnalysisResult, remove label_scan from MealDocument.source <!-- id:1ximgmm -->
  - In src/lib/types/meal.ts, remove quantity and unit fields from AnalysedFoodItem (or RecognisedFoodItem)
  - Remove totalMacros, provider, processingTimeMs from FoodAnalysisResult (or FoodRecognitionResult)
  - Remove label_scan from MealDocument.source union type
  - Update any imports/usages across codebase
  - Stream: 1
  - Requirements: [6.3](requirements.md#6.3)

- [x] 2. Define IRecognitionService interface, RecognitionError class, and canonical types in src/lib/services/recognition.ts <!-- id:1ximgmn -->
  - Create src/lib/services/recognition.ts with IRecognitionService interface: analyse(image: Blob), isReady(), getBackendType()
  - Define FoodAnalysisResult: { items: AnalysedFoodItem[], overallConfidence: number, notes?: string }
  - Define AnalysedFoodItem: { name: string, carbs: number, protein: number, fat: number, confidence: number }
  - Define RecognitionError class with code: RecognitionErrorCode and optional httpStatus
  - RecognitionErrorCode: TIMEOUT | NOT_CONFIGURED | BACKEND_ERROR | INVALID_RESPONSE | NO_ITEMS
  - Export createRecognitionService() factory stub (implementation in later task)
  - Stream: 1
  - Requirements: [5.6](requirements.md#5.6)

## Mock Recognition Service

- [x] 3. Write failing unit tests for MockRecognitionService <!-- id:1ximgmo -->
  - Create src/lib/services/mock-recognition.test.ts
  - Test isReady() returns true
  - Test getBackendType() returns mock
  - Test analyse() returns FoodAnalysisResult matching schema (Req 5.2)
  - Test result items array has 2-4 entries (Req 5.3)
  - Test all items have non-negative macro values
  - Test notes field contains [MOCK] prefix (Req 5.5)
  - Test artificial delay is between 500ms-1500ms using vi.useFakeTimers() (Req 5.4)
  - Blocked-by: 1ximgmn (Define IRecognitionService interface, RecognitionError class, and canonical types in src/lib/services/recognition.ts)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6)

- [x] 4. Implement MockRecognitionService <!-- id:1ximgmp -->
  - Create src/lib/services/mock-recognition.ts
  - Implement IRecognitionService with isReady()=true, getBackendType()=mock
  - analyse() waits 500-1500ms random delay then returns MOCK_RESULT constant
  - Mock data: grilled chicken breast (0/31/3.6), steamed broccoli (7/3/0.4), brown rice 1 cup (45/5/1.6)
  - notes field: [MOCK] Simulated response — no backend call was made.
  - Blocked-by: 1ximgmo (Write failing unit tests for MockRecognitionService)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6)

## HTTP Recognition Service

- [ ] 5. Write failing unit tests for parseAnalysisResult <!-- id:1ximgmq -->
  - Create tests in src/lib/services/http-recognition.test.ts
  - Test extracts JSON from markdown-fenced response (strips ```json wrapper)
  - Test throws RecognitionError(INVALID_RESPONSE) when content is not parseable JSON
  - Test throws RecognitionError(INVALID_RESPONSE) when required fields missing or wrong type
  - Test throws RecognitionError(NO_ITEMS) when items array is empty
  - Test returns valid FoodAnalysisResult for well-formed OpenAI-compat response envelope
  - Test handles choices[0].message.content as string or object
  - Blocked-by: 1ximgmn (Define IRecognitionService interface, RecognitionError class, and canonical types in src/lib/services/recognition.ts)
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2)

- [ ] 6. Implement parseAnalysisResult function <!-- id:1ximgmr -->
  - Add parseAnalysisResult() to src/lib/services/http-recognition.ts
  - Extract content string from choices[0].message.content
  - If content starts with ``` (markdown fence), strip the fence
  - JSON.parse the resulting string
  - Validate required fields: items (array), overallConfidence (number 0-1)
  - For each item: validate name (string), carbs/protein/fat (non-negative number), confidence (0-1)
  - Throw RecognitionError(INVALID_RESPONSE) on any schema violation
  - Throw RecognitionError(NO_ITEMS) if items.length === 0
  - Blocked-by: 1ximgmq (Write failing unit tests for parseAnalysisResult)
  - Stream: 1
  - Requirements: [6.2](requirements.md#6.2)

- [ ] 7. Write failing unit tests for HttpRecognitionService <!-- id:1ximgms -->
  - Add tests to src/lib/services/http-recognition.test.ts
  - Test isReady() returns false when RECOGNITION_BASE_URL or RECOGNITION_MODEL unset
  - Test isReady() returns true when both are set
  - Test analyse() throws RecognitionError(TIMEOUT) when fetch aborted after timeout
  - Test analyse() throws RecognitionError(BACKEND_ERROR, httpStatus) for non-200 responses
  - Test analyse() omits Authorization header when RECOGNITION_API_KEY not set
  - Test analyse() includes Authorization: Bearer {key} when key is set
  - Test RECOGNITION_TIMEOUT_MS env var is read and used (default 10000)
  - Mock fetch to verify correct OpenAI-compat request body shape
  - Blocked-by: 1ximgmn (Define IRecognitionService interface, RecognitionError class, and canonical types in src/lib/services/recognition.ts)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [11.2](requirements.md#11.2)

- [ ] 8. Implement HttpRecognitionService <!-- id:1ximgmt -->
  - Create src/lib/services/http-recognition.ts
  - Implement IRecognitionService: reads RECOGNITION_BASE_URL, RECOGNITION_MODEL, RECOGNITION_API_KEY, RECOGNITION_TIMEOUT_MS from $env/dynamic/private
  - isReady(): true when baseUrl and model are non-empty
  - getBackendType(): returns http
  - analyse(): POST to {baseUrl}/v1/chat/completions with OpenAI-compat body (model, messages with base64 image, response_format: json_object)
  - Use AbortController with configurable timeout (default 10s)
  - Conditionally include Authorization: Bearer header only when API key is set
  - Use parseAnalysisResult() to parse response
  - Throw RecognitionError with appropriate codes for timeout, backend error
  - Blocked-by: 1ximgmr (Implement parseAnalysisResult function), 1ximgms (Write failing unit tests for HttpRecognitionService)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [5.6](requirements.md#5.6), [11.2](requirements.md#11.2)

## Factory & API Layer

- [ ] 9. Write failing unit tests for createRecognitionService() factory <!-- id:1ximgmu -->
  - Add tests to src/lib/services/recognition.test.ts
  - Test returns MockRecognitionService when RECOGNITION_MOCK_MODE=true
  - Test returns HttpRecognitionService when RECOGNITION_MOCK_MODE=false
  - Test returns HttpRecognitionService when RECOGNITION_MOCK_MODE is unset
  - Blocked-by: 1ximgmp (Implement MockRecognitionService), 1ximgmt (Implement HttpRecognitionService)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.6](requirements.md#5.6)

- [ ] 10. Implement createRecognitionService() factory <!-- id:1ximgmv -->
  - In src/lib/services/recognition.ts, implement createRecognitionService()
  - Import env from $env/dynamic/private (server-side only)
  - Return new MockRecognitionService() when env[RECOGNITION_MOCK_MODE] === true
  - Return new HttpRecognitionService() otherwise
  - Blocked-by: 1ximgmu (Write failing unit tests for createRecognitionService() factory)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.6](requirements.md#5.6)

- [ ] 11. Write failing unit tests for /api/recognition/status endpoint <!-- id:1ximgmw -->
  - Create src/routes/api/recognition/status/+server.test.ts
  - Test returns { configured: true, mockMode: false } when base URL and model are set
  - Test returns { configured: false, mockMode: false } when base URL or model missing
  - Test returns { configured: true, mockMode: true } when RECOGNITION_MOCK_MODE=true
  - Test returns { configured: false, mockMode: false } (fail-open) when service constructor throws
  - Blocked-by: 1ximgmv (Implement createRecognitionService() factory)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.5](requirements.md#5.5)

- [ ] 12. Implement /api/recognition/status endpoint <!-- id:1ximgmx -->
  - Create src/routes/api/recognition/status/+server.ts
  - GET handler calls createRecognitionService()
  - Returns json({ configured: service.isReady(), mockMode: service.getBackendType() === mock })
  - Wrap in try/catch: any error returns { configured: false, mockMode: false } with status 200
  - Blocked-by: 1ximgmw (Write failing unit tests for /api/recognition/status endpoint)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.5](requirements.md#5.5)

- [ ] 13. Write failing unit tests for /api/recognition/analyse endpoint <!-- id:1ximgmy -->
  - Create src/routes/api/recognition/analyse/+server.test.ts
  - Test returns 503 when service is not configured (not ready)
  - Test returns 504 on RecognitionError(TIMEOUT)
  - Test returns 422 on RecognitionError(NO_ITEMS)
  - Test returns 413 when imageBase64 exceeds 14,000,000 characters
  - Test returns 429 when upstream returns 429 (RecognitionError(BACKEND_ERROR, 429))
  - Test returns 200 with FoodAnalysisResult on success
  - Test all error messages use Irish English spelling (Req 11.4)
  - Blocked-by: 1ximgmv (Implement createRecognitionService() factory)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [6.6](requirements.md#6.6), [11.2](requirements.md#11.2), [11.4](requirements.md#11.4)

- [ ] 14. Implement /api/recognition/analyse endpoint <!-- id:1ximgmz -->
  - Create src/routes/api/recognition/analyse/+server.ts
  - POST handler: parse request body { imageBase64, mimeType }
  - Validate image size: reject if imageBase64.length > 14,000,000 with 413
  - Call createRecognitionService(), check isReady() — return 503 if not
  - Convert base64 to Blob, call service.analyse(blob)
  - Map RecognitionError codes to HTTP status: TIMEOUT->504, BACKEND_ERROR(429)->429, BACKEND_ERROR->503, NO_ITEMS->422, INVALID_RESPONSE->502
  - Return 200 with FoodAnalysisResult on success
  - All user-facing error messages in Irish English (Req 11.4)
  - Blocked-by: 1ximgmy (Write failing unit tests for /api/recognition/analyse endpoint)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [5.1](requirements.md#5.1), [6.1](requirements.md#6.1), [6.6](requirements.md#6.6), [11.2](requirements.md#11.2), [11.4](requirements.md#11.4)

## Cleanup

- [ ] 15. Remove old Anthropic SDK, old services, old API routes, and label scanning code <!-- id:1ximgn0 -->
  - Run: pnpm remove @anthropic-ai/sdk
  - Delete src/lib/services/claude-food-recognition.ts
  - Delete or gut src/lib/services/food-recognition.ts (replaced by recognition.ts)
  - Delete src/routes/api/ai/recognise/+server.ts (replaced by /api/recognition/analyse)
  - Remove or rewrite src/lib/components/FoodRecognitionResult.svelte — no longer displays quantity/unit/provider/processingTimeMs
  - Remove any LabelContext types or label scanning UI code
  - Update src/lib/services/index.ts and any other barrel exports
  - Blocked-by: 1ximgmz (Implement /api/recognition/analyse endpoint)
  - Stream: 1
  - Requirements: [5.6](requirements.md#5.6)

## Frontend Components

- [x] 16. Implement MockModeBanner.svelte component <!-- id:1ximgn1 -->
  - Create src/lib/components/MockModeBanner.svelte
  - Static display component — no props needed
  - Amber/yellow visual styling to clearly distinguish from production UI
  - Text: Mock mode — responses are simulated, no backend calls are being made
  - Stream: 2
  - Requirements: [5.5](requirements.md#5.5)

- [x] 17. Implement ManualEntryCTA.svelte component <!-- id:1ximgn2 -->
  - Create src/lib/components/ManualEntryCTA.svelte
  - Static display component — no props needed
  - Shows message: Food recognition is not configured.
  - Link to /manual: Enter meal manually
  - Hint text referencing RECOGNITION_BASE_URL and RECOGNITION_MODEL env vars and .env file
  - Link to /docs/setup for setup guide
  - Stream: 2
  - Requirements: [4.4](requirements.md#4.4)

- [x] 18. Write failing tests for CameraCapture.svelte stream cleanup and camera detection <!-- id:1ximgn3 -->
  - Create or extend src/lib/components/CameraCapture.test.ts
  - Test stream tracks are stopped on component destroy (mock MediaStream)
  - Test camera-available check returns false when enumerateDevices has no videoinput
  - Test camera-available check returns false when getUserMedia is not supported
  - Test camera viewfinder shown when any videoinput device detected (D-MVR-018)
  - Test gallery upload path triggers same onCapture callback as camera path
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 19. Update CameraCapture.svelte: stream cleanup, enumerateDevices detection, gallery preview parity <!-- id:1ximgn4 -->
  - Add onDestroy + beforeNavigate handlers to stop MediaStream tracks (Req 2.4)
  - Replace UA-string detection with enumerateDevices() videoinput feature detection (D-MVR-011, D-MVR-018)
  - If no camera device detected: render gallery-only input — no viewfinder shown
  - Gallery file input (image/jpeg,image/png) passes Blob through same ImagePreview component as camera path (Req 3.2)
  - Both camera and gallery paths call same onCapture callback (Req 3.3)
  - Blocked-by: 1ximgn3 (Write failing tests for CameraCapture.svelte stream cleanup and camera detection)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 20. Write failing tests for MealEditor.svelte mockMode prop and save failure state retention <!-- id:1ximgn5 -->
  - Extend src/lib/components/MealEditor.test.ts
  - Test MockModeBanner renders when mockMode=true prop is passed
  - Test MockModeBanner does not render when mockMode=false or undefined
  - Test editor items/macros state is retained in memory when save API call fails
  - Test error toast with Irish English text is shown on save failure
  - Blocked-by: 1ximgn1 (Implement MockModeBanner.svelte component)
  - Stream: 2
  - Requirements: [5.5](requirements.md#5.5), [11.1](requirements.md#11.1)

- [x] 21. Update MealEditor.svelte: add mockMode prop, render MockModeBanner, retain state on failed save <!-- id:1ximgn6 -->
  - Add mockMode?: boolean prop to MealEditor
  - Render MockModeBanner when mockMode is true
  - On failed POST /api/meals: show error toast, do NOT clear editor items state
  - Error toast text (Irish English): Service unavailable — meal not saved.
  - Blocked-by: 1ximgn1 (Implement MockModeBanner.svelte component), 1ximgn5 (Write failing tests for MealEditor.svelte mockMode prop and save failure state retention)
  - Stream: 2
  - Requirements: [5.5](requirements.md#5.5), [11.1](requirements.md#11.1), [11.4](requirements.md#11.4)

## Frontend Integration

- [ ] 22. Write failing tests for capture page status detection and conditional rendering <!-- id:1ximgn7 -->
  - Create or extend src/routes/capture/+page.test.ts
  - Test skeleton/loading state shown while /api/recognition/status is in-flight
  - Test ManualEntryCTA renders when status returns { configured: false, mockMode: false }
  - Test MockModeBanner renders when status returns { configured: true, mockMode: true }
  - Test recognition path renders when status returns { configured: true, mockMode: false }
  - Test ManualEntryCTA renders as safe default when /api/recognition/status request fails
  - Blocked-by: 1ximgmx (Implement /api/recognition/status endpoint), 1ximgn1 (Implement MockModeBanner.svelte component), 1ximgn2 (Implement ManualEntryCTA.svelte component)
  - Stream: 2
  - Requirements: [4.4](requirements.md#4.4), [5.5](requirements.md#5.5)

- [ ] 23. Update /capture/+page.svelte: fetch status, conditional rendering, wire handleSave, image size check <!-- id:1ximgn8 -->
  - On page mount: fetch GET /api/recognition/status; store result as { configured, mockMode }
  - Show skeleton/loading state during status fetch (prevents layout shift)
  - On fetch error: default to { configured: false, mockMode: false }
  - If !configured && !mockMode: render ManualEntryCTA, hide recognition path
  - If mockMode: render MockModeBanner above capture UI
  - Pass mockMode prop into MealEditor when navigating to edit step
  - Client-side 10MB image size check before calling /api/recognition/analyse
  - Wire handleSave() stub — POST /api/meals + image upload to Blob Storage
  - Blocked-by: 1ximgn4 (Update CameraCapture.svelte: stream cleanup, enumerateDevices detection, gallery preview parity), 1ximgn6 (Update MealEditor.svelte: add mockMode prop, render MockModeBanner, retain state on failed save), 1ximgn7 (Write failing tests for capture page status detection and conditional rendering)
  - Stream: 2
  - Requirements: [4.4](requirements.md#4.4), [5.5](requirements.md#5.5), [6.1](requirements.md#6.1), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5)

## Config & Docs

- [x] 24. Update vite.config.ts: add HTTPS via @vitejs/plugin-basic-ssl and LAN binding <!-- id:1ximgn9 -->
  - Run: pnpm add -D @vitejs/plugin-basic-ssl
  - Import basicSsl from @vitejs/plugin-basic-ssl in vite.config.ts
  - Add basicSsl() to plugins array
  - Add server: { host: true, port: 5173 } to bind to 0.0.0.0 for LAN access
  - Dev server becomes HTTPS-only at https://localhost:5173 (D-MVR-010)
  - Stream: 3
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3)

- [x] 25. Update .env.example with provider-agnostic recognition env vars <!-- id:1ximgna -->
  - Replace ANTHROPIC_API_KEY with new recognition env vars
  - Add RECOGNITION_BASE_URL= with comment showing examples (Ollama, DeepSeek, custom)
  - Add RECOGNITION_MODEL= with comment
  - Add RECOGNITION_API_KEY= with comment (optional for local endpoints)
  - Add RECOGNITION_MOCK_MODE=false with comment explaining mock mode
  - Add RECOGNITION_TIMEOUT_MS=10000 with comment about increasing for local models
  - Keep AZURE_COSMOS_CONNECTION_STRING and AZURE_BLOB_STORAGE_URL
  - Stream: 3
  - Requirements: [4.2](requirements.md#4.2), [5.1](requirements.md#5.1)

- [x] 26. Update developer docs with provider-agnostic setup guide <!-- id:1ximgnb -->
  - Add or update setup section in README.md or docs/setup.md
  - Step-by-step: pnpm install, cp .env.example .env, configure recognition backend
  - Option A: Local Ollama (free, no account) with example config
  - Option B: Cloud model (DeepSeek, etc.) with example config
  - Option C: Mock mode (RECOGNITION_MOCK_MODE=true)
  - HTTPS note: dev server is now https://localhost:5173
  - Mobile testing: find LAN IP, visit https://192.168.x.x:5173, accept cert warning
  - Note: increase RECOGNITION_TIMEOUT_MS for large local models
  - Stream: 3
  - Requirements: [4.1](requirements.md#4.1)

## Validation Tests

- [x] 27. Extend macros.test.ts with property-based tests using fast-check <!-- id:1ximgnc -->
  - Extend src/lib/utils/macros.test.ts with fast-check property tests
  - Property: sumMacros(items).totalCarbs === sum of all item.carbs for any valid item array
  - Property: sumMacros([]) returns zero totals
  - Property: all totals are non-negative when item values are non-negative
  - Use fc.array(fc.record({ carbs, protein, fat with fc.float min:0 max:200 })) for generators
  - Stream: 1
  - Requirements: [6.3](requirements.md#6.3)

- [x] 28. Write component tests for manual entry flow <!-- id:1ximgnd -->
  - Create or extend src/routes/manual/+page.test.ts
  - Test form renders with name, carbs, protein, fat fields (Req 7.1)
  - Test multiple items can be added before save (Req 7.2)
  - Test saved meal has source: manual (Req 7.3)
  - Mock POST /api/meals and verify correct payload including source field
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)

- [x] 29. Write component tests for logbook display and meal edit/delete <!-- id:1ximgne -->
  - Create or extend src/routes/+page.test.ts
  - Test meals render ordered by timestamp DESC (Req 8.1)
  - Test each entry shows total carbs, protein, fat, source, timestamp (Req 8.2)
  - Test expanding a meal entry shows per-item macros (Req 8.3)
  - Test edit flow: MealEditor opens, PUT request fired on save (Req 8.4)
  - Test delete flow: confirmation modal shown, DELETE request fired on confirm (Req 8.5)
  - Stream: 2
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5)

- [x] 30. Write component tests for preset save, apply, edit, and delete <!-- id:1ximgnf -->
  - Create or extend src/routes/presets/+page.test.ts
  - Test save as preset: POST /api/presets with name and category (Req 9.1)
  - Test presets page: presets grouped by meal/snack category (Req 9.2)
  - Test apply preset: POST /api/meals with source: preset (Req 9.3)
  - Test edit preset: PUT /api/presets/[id] with updated fields (Req 9.4)
  - Test delete preset: DELETE /api/presets/[id] after confirmation (Req 9.4)
  - Stream: 2
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4)

- [ ] 31. Audit and fix Irish English spelling in all user-facing strings <!-- id:1ximgng -->
  - Search all .svelte and +server.ts files for US English spellings: recognized, organization, color, canceled, etc.
  - Fix to Irish English equivalents: recognised, organisation, colour, cancelled
  - Key files: capture page, MealEditor, manual entry, logbook, API error responses in analyse and meals endpoints
  - Verify toast messages, inline errors, and placeholder text all use Irish English
  - Blocked-by: 1ximgmz (Implement /api/recognition/analyse endpoint), 1ximgn8 (Update /capture/+page.svelte: fetch status, conditional rendering, wire handleSave, image size check)
  - Stream: 1
  - Requirements: [11.4](requirements.md#11.4)
