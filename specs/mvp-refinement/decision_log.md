# MVP Refinement — Decision Log

## D-MVR-001: Camera scope is mobile-only
**Date:** 2026-03-12
**Decision:** Camera capture targets mobile phones only. Desktop browsers show gallery upload.
**Rationale:** Food photography is inherently a mobile activity. Desktop webcams produce poor results for food photos. Simplifies testing matrix.
**Status:** Approved

## D-MVR-002: Local dev only (no cloud deployment)
**Date:** 2026-03-12
**Decision:** Target environment is local development server. No cloud deployment in this spec.
**Rationale:** Reduces scope. Azure backend is already provisioned; only the frontend dev server needs to be accessible.
**Status:** Approved

## D-MVR-003: HTTPS via self-signed cert (simplest approach)
**Date:** 2026-03-12
**Decision:** Use Vite's basic SSL plugin or equivalent for HTTPS in dev. No external tunnels.
**Rationale:** User chose "whatever works" — self-signed cert is the simplest zero-config approach for getUserMedia on mobile.
**Status:** Approved

## D-MVR-004: Mock AI mode for dev testing
**Date:** 2026-03-12
**Decision:** Add a mock AI service behind an `AI_MOCK_MODE` env var that returns realistic fake food data.
**Rationale:** Enables full flow testing without API credits. User explicitly requested this.
**Status:** Approved

## D-MVR-005: Clean slate — no data migration
**Date:** 2026-03-12
**Decision:** No data migration needed. Cosmos DB is empty.
**Rationale:** dev-sdd has never been deployed with real data.
**Status:** Approved

## D-MVR-006: Feature name is mvp-refinement
**Date:** 2026-03-12
**Decision:** Spec directory and branch named `mvp-refinement`.
**Rationale:** User preference — emphasises the fix/improve aspect over pure validation.
**Status:** Approved

## D-MVR-007: API key from console.anthropic.com (separate from Claude Pro)
**Date:** 2026-03-12
**Decision:** Document that Claude Pro subscription ≠ API access. User needs a separate API key from console.anthropic.com (free $5 credits available).
**Rationale:** User was unaware of the distinction. Clear documentation prevents confusion.
**Status:** Superseded by D-MVR-013 — Anthropic is no longer a direct backend. Claude is accessible only via an OpenAI-compat proxy (e.g. LiteLLM). `ANTHROPIC_API_KEY` is removed from `.env.example`.

## D-MVR-008: Frontend AI status via /api/ai/status endpoint
**Date:** 2026-03-12
**Decision:** Capture page calls a new GET `/api/ai/status` endpoint on mount to determine whether to show the AI flow or ManualEntryCTA. Status is the single source of truth for mockMode — no dual-signal via response headers.
**Rationale:** User approved this approach. Status endpoint is more reliable than try-and-fail recognition, and cleaner than a build-time env var that requires a rebuild to change.
**Status:** Approved

## D-MVR-009: Mock banner in both capture page and MealEditor
**Date:** 2026-03-12
**Decision:** MockModeBanner renders on the capture page (from status endpoint result) and in MealEditor (via mockMode prop passed down). Persists through the full flow.
**Rationale:** User approved. Developer should always know they're in mock mode regardless of which step they're on.
**Status:** Approved

## D-MVR-010: HTTPS changes localhost to https:// (no more http://)
**Date:** 2026-03-12
**Decision:** `@vitejs/plugin-basic-ssl` makes the dev server HTTPS-only. `http://localhost:5173` no longer works — dev moves to `https://localhost:5173`.
**Rationale:** `basicSsl` cannot serve both HTTP and HTTPS. Req 1.4 ("existing HTTP localhost workflow continues") is interpreted as: non-camera features continue to work under the new HTTPS URL. The protocol change is acceptable and documented in setup guide.
**Status:** Approved

## D-MVR-011: Camera detection via enumerateDevices (not UA string)
**Date:** 2026-03-12
**Decision:** Use `navigator.mediaDevices.enumerateDevices()` to detect videoinput devices rather than UA-string heuristics for mobile/desktop detection.
**Rationale:** UA detection is unreliable (iPads in desktop mode, custom UA strings). Feature detection correctly identifies whether any camera is available regardless of device type.
**Status:** Approved — relaxed by D-MVR-018 (camera viewfinder shown for any detected camera, including MacBook FaceTime).

## D-MVR-012: Empty items array returns 422 from recognise endpoint
**Date:** 2026-03-12
**Decision:** If the backend returns a response with zero food items, the `/api/recognition/analyse` endpoint returns 422 rather than 200 with an empty array.
**Rationale:** Eliminates client-side ambiguity between "success with nothing" and "recognised failure". All recognition failure modes map to non-200 responses, making the client error handler uniform.
**Status:** Approved

## D-MVR-013: Provider-agnostic recognition layer — no vendor SDK
**Date:** 2026-03-13
**Decision:** All recognition backends (including Claude) are accessed via plain `fetch` calls to an OpenAI-compatible `/v1/chat/completions` endpoint. The Anthropic SDK is removed. No vendor-specific code exists in the application layer.
**Rationale:** Application must be independent of Anthropic and any specific AI paradigm. Config-only backend switching enables the path to a custom SLM. On-device inference is a future goal — keeping the interface HTTP-based and stateless is compatible with that.
**Status:** Approved

## D-MVR-014: OpenAI-compat as the standard wire format
**Date:** 2026-03-13
**Decision:** Standardise on OpenAI-compatible `/v1/chat/completions` as the wire format for all recognition backends. Backends that don't natively support it (e.g. Anthropic's native API) are handled by a thin private adapter inside `HttpRecognitionService`.
**Rationale:** OpenAI-compat is the de-facto standard supported by Ollama, DeepSeek, LM Studio, and most self-hosted inference servers. The future custom SLM will expose the same interface, making the application fully forward-compatible without code changes.
**Status:** Approved

## D-MVR-015: Terminology purge — no "AI" in service layer
**Date:** 2026-03-13
**Decision:** Rename all service-layer identifiers to remove AI/vendor connotations: `IFoodRecognitionService` → `IRecognitionService`, `recognise()` → `analyse()`, `isConfigured()` → `isReady()`, `/api/ai/` routes → `/api/recognition/`, `AI_MOCK_MODE` → `RECOGNITION_MOCK_MODE`, `ANTHROPIC_API_KEY` → `RECOGNITION_API_KEY`.
**Rationale:** The service may eventually run a custom on-device model with no AI/cloud component. Naming should reflect what the service does (recognise food from images) not how it does it.
**Status:** Approved

## D-MVR-018: Req 2.5 camera detection relaxed to "any camera"
**Date:** 2026-03-13
**Decision:** Camera viewfinder is shown whenever `enumerateDevices()` finds any `videoinput` device — including MacBook FaceTime cameras. Req 2.5 ("desktop shows gallery only") is relaxed to "show camera if any camera is detected; gallery upload always available as alternative."
**Rationale:** Distinguishing rear-facing from front-facing cameras requires acquiring a media stream (which requires permission), making it impractical for a pre-permission detection step. The gallery upload is always shown alongside the camera, so desktop users are not blocked. The original requirement assumed desktops would have no camera — this is no longer universally true.
**Status:** Approved

## D-MVR-017: Label scanning removed from scope
**Date:** 2026-03-13
**Decision:** Label scanning (Req 10) is removed from scope entirely. The `LabelContext` type, dual-image capture flow, and all `labelBase64`/`labelMimeType` fields are deleted. `analyse()` accepts a single image only. `source: 'label_scan'` is removed from `MealDocument`.
**Rationale:** Label scanning adds multi-image backend compatibility concerns that complicate the provider-agnostic layer without delivering core value for MVP validation. Single-image recognition is sufficient. Label scanning can be re-evaluated post-SLM if needed.
**Status:** Approved

## D-MVR-016: SLM serving mechanism left open
**Date:** 2026-03-13
**Decision:** The serving infrastructure for the future custom SLM is not specified in this design. The design only documents the interface contract the SLM must satisfy.
**Rationale:** Serving decisions depend on model size and target runtime (server vs. on-device), which are unknown until fine-tuning experiments are complete. The OpenAI-compat interface is runtime-agnostic — any serving framework that exposes it will work.
**Status:** Approved
