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
**Status:** Approved
