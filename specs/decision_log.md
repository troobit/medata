# MeData Decision Log

This document records all decisions made during the requirements and design phases.

---

## Requirements Phase Decisions

### D-REQ-001: Backwards Compatibility
**Date:** 2026-02-03
**Question:** Is backwards compatibility a concern?
**Decision:** No - this is a greenfield project with no existing data or APIs to maintain.
**Rationale:** Starting fresh allows optimal design without legacy constraints.

### D-REQ-002: AI Provider Requirements
**Date:** 2026-02-03
**Question:** Which AI providers are required for MVP?
**Decision:** Any single configured provider is sufficient for MVP.
**Rationale:** Reduces MVP complexity. Fallback chains are nice-to-have, not required.
**Impact:** Requirement 2.8 specifies "at least one" provider; 2.9 makes fallback a SHOULD.

### D-REQ-003: AI Failure Handling
**Date:** 2026-02-03
**Question:** What happens when AI food recognition fails completely?
**Decision:** Manual entry fallback is required.
**Rationale:** Users must always be able to log meals regardless of AI availability.
**Impact:** Requirement 2.7 mandates fallback to manual entry on failure.

### D-REQ-004: Confidence Threshold
**Date:** 2026-02-03
**Question:** What confidence threshold should trigger review flags?
**Decision:** No threshold - display all results regardless of confidence.
**Rationale:** Let the user decide what's acceptable; avoid paternalistic filtering.
**Impact:** Requirement 2.4 specifies showing all results; no filtering logic needed.

### D-REQ-005: Photo Requirement
**Date:** 2026-02-03
**Question:** Should photos be required when logging meals?
**Decision:** Photos are optional.
**Rationale:** Users should be able to log meals via manual entry or presets without photos.
**Impact:** Requirement 3.5 explicitly allows manual entry without photos.

### D-REQ-006: Data Export
**Date:** 2026-02-03
**Question:** What export formats are required for MVP?
**Decision:** Export is out of scope for MVP.
**Rationale:** Focus MVP on core food logging; export can be added post-MVP.
**Impact:** Export requirements deferred to post-MVP phases.

### D-REQ-007: MVP Value Proposition
**Date:** 2026-02-03
**Question:** What is the value of food-only MVP without BSL/insulin correlation?
**Decision:** Food macro estimation alone has immense value.
**Rationale:** Estimating food macro content when eating out is highly variable and difficult for humans. Accurate macro capture is valuable independently of diabetes data correlation.
**Impact:** MVP scope validated - food capture is the core value proposition.

### D-REQ-008: Offline Support
**Date:** 2026-02-03
**Question:** How should the system handle offline scenarios?
**Decision:** MVP is online-only. Offline support deferred.
**Rationale:** Simplifies MVP scope. Network failures display error messages rather than queueing.
**Impact:** Requirement 10.6 updated; NF.8 added as constraint.

### D-REQ-009: Browser Support
**Date:** 2026-02-03
**Question:** Which browsers are supported?
**Decision:** Mobile-first, no explicit browser support matrix.
**Rationale:** Focus on mobile experience. No automated testing beyond mathematical validation.
**Impact:** Requirements updated to "modern mobile browsers" rather than specific versions.

### D-REQ-010: Meal History Access
**Date:** 2026-02-03
**Question:** How does the user view saved meals?
**Decision:** Logbook view for meal history (same pattern as future insulin/BSL/exercise data).
**Rationale:** Consistent UI pattern across all data types.
**Impact:** Section 8 (Meal History and Logbook) added to requirements.

### D-REQ-011: Authentication
**Date:** 2026-02-03
**Question:** What is the authentication model?
**Decision:** Single-user application with no authentication.
**Rationale:** Strictly out of scope for MVP. Simplifies architecture.
**Impact:** Requirement 11.6 and NF.9 added as explicit constraints.

### D-REQ-012: API Key Storage
**Date:** 2026-02-03
**Question:** How should AI API keys be stored?
**Decision:** Environment variables for deployment, local fallback for development.
**Rationale:** Standard practice for secrets management.
**Impact:** Requirement 11.1 updated.

### D-REQ-013: Nutrition Label Format
**Date:** 2026-02-03
**Question:** Which regional nutrition label formats are supported?
**Decision:** Australian format only for MVP.
**Rationale:** Owner's region. Other formats can be added post-MVP.
**Impact:** Requirement 7.2 specifies Australian-format labels.

### D-REQ-014: Zero AI Results Handling
**Date:** 2026-02-03
**Question:** What happens when AI recognition succeeds but returns zero items?
**Decision:** Display error with option to retry or proceed with manual entry.
**Rationale:** Treat empty results as a recoverable error state.
**Impact:** Requirement 2.10 added.

### D-REQ-015: Edit Saved Meals
**Date:** 2026-02-03
**Question:** Can saved meals be edited after storage?
**Decision:** Yes, saved meals can be edited.
**Rationale:** Users need to correct errors discovered after saving.
**Impact:** Requirement 8.4 added to Meal History section.

### D-REQ-016: Remove Calorie Input
**Date:** 2026-02-03
**Question:** Should calories be a separate input field?
**Decision:** Remove calorie input. Focus on carbs, protein, fat only.
**Rationale:** Calories can be derived from macros (4/4/9 rule). Reduces input friction. Owner primarily cares about carbs for insulin dosing.
**Impact:** Requirements 2.2, 3.1 updated to remove calories. 3.7 added for frictionless carb/fat editing.

### D-REQ-017: Frictionless Input Priority
**Date:** 2026-02-03
**Question:** What is the priority for input UX?
**Decision:** Minimal friction is paramount. Name + carbs + fat with large tap targets for quick adjustment.
**Rationale:** Logging must not feel like a chore. Speed of input directly affects adoption.
**Impact:** Requirement 3.7 added. Manual entry form simplified.

### D-REQ-018: Preset Simplification
**Date:** 2026-02-03
**Question:** What preset features are needed for MVP?
**Decision:** Simplified presets - removed last-used tracking and surfacing. Allow emoji-only names.
**Rationale:** Reduce complexity. Focus on core save/apply functionality.
**Impact:** Requirements 6.4 and 6.5 removed. 6.1 updated to allow emoji names.

### D-REQ-019: Label Scan Serving Estimation
**Date:** 2026-02-03
**Question:** How should serving size be determined from nutrition labels?
**Decision:** After scanning label, user photographs actual food to estimate servings consumed.
**Rationale:** More accurate than manual serving entry. Uses existing photo capture capability.
**Impact:** Requirement 7.4 changed to photo-based serving estimation.

### D-REQ-020: Requirements Approval
**Date:** 2026-02-03
**Decision:** Requirements v1.2 approved by Owner.
**Status:** Requirements phase complete. Ready for design phase.

---

## Design Phase Decisions

### D-DES-001: AI Response Format
**Date:** 2026-02-04
**Question:** Should the system request structured JSON output or parse free-text responses from AI?
**Decision:** Use structured JSON mode from AI providers.
**Rationale:** Reliable parsing, no ambiguity, all major providers support structured output.
**Impact:** AI service implementations must use JSON mode; response schemas defined in design.

### D-DES-002: Image Retention Policy
**Date:** 2026-02-04
**Question:** How long should meal images be retained?
**Decision:** Images auto-deleted after 30 days; macro data retained indefinitely.
**Rationale:** Balances storage costs with utility. After 30 days, images are rarely referenced.
**Impact:** Blob storage needs TTL policy or cleanup job. imageUrl field may become stale.

### D-DES-003: Client/Server Boundary
**Date:** 2026-02-04
**Question:** Where does business logic execute?
**Decision:** Research and follow SvelteKit best practices. Business logic in server-side services, client only handles UI state.
**Rationale:** Security (API keys) and data access (Cosmos DB) require server-side execution.
**Impact:** Services are server-side only; client uses fetch to API routes.

### D-DES-004: Expired Image Handling
**Date:** 2026-02-04
**Question:** What happens when a meal's image URL expires?
**Decision:** Display placeholder image or "Image not available" text.
**Rationale:** Simple, honest UX. No complex detection needed - just handle 404s gracefully.
**Impact:** MealDetail component needs error handling for image load failures.

### D-DES-005: AI Prompt Design
**Date:** 2026-02-04
**Question:** What prompt is sent to the AI for food recognition?
**Decision:** Research and design optimal prompt. Core intent: "Identify foods and estimate carbohydrates, fats, and proteins on this plate."
**Rationale:** Prompt engineering is critical for accuracy. Requires research and iteration.
**Impact:** Add research task for prompt design. Document final prompt in design.

### D-DES-006: Label Scanning Approach
**Date:** 2026-02-04
**Question:** How does label scanning work?
**Decision:** Unified capture flow - label scanning is optional context for the standard food recognition, not a separate workflow.
**Rationale:** Simpler UX. Users photograph food first; can optionally add label for packaged foods. AI uses label data (if provided) to improve accuracy.
**Impact:** Single AI endpoint accepts food image + optional label image. No separate label/portion endpoints.

### D-DES-007: Meal Pagination Strategy
**Date:** 2026-02-04
**Question:** How are meals paginated?
**Decision:** Paginate by day. All views are day-based.
**Rationale:** Users think about food in terms of days. Aligns with logbook mental model.
**Impact:** API returns meals grouped by day. Partition key could be date-based.

### D-DES-008: Settings/Configuration
**Date:** 2026-02-04
**Question:** Where is AI provider configured?
**Decision:** Environment variables only. No in-app settings UI for MVP.
**Rationale:** Single-user app. Simplifies MVP. Owner sets env vars at deployment.
**Impact:** No settings route needed. Document required env vars.

### D-DES-009: First-Run Experience
**Date:** 2026-02-04
**Question:** What do users see on first run?
**Decision:** Empty app with landing page showing logging buttons (capture, manual entry, presets).
**Rationale:** Simple, functional. No onboarding wizard needed.
**Impact:** Home page always shows action buttons regardless of data state.

### D-DES-010: Image Upload Method
**Date:** 2026-02-04
**Question:** How are images uploaded to Azure Blob Storage?
**Decision:** Follow Microsoft's Azure Blob Storage recommendations for SvelteKit. Server-side upload using @azure/storage-blob SDK.
**Rationale:** Security (keys stay server-side), reliability, follows platform best practices.
**Impact:** Research Azure docs. Implement server-side upload endpoint.

### D-DES-011: Mobile Testing Strategy
**Date:** 2026-02-04
**Question:** How is mobile functionality validated without automated browser tests?
**Decision:** User testing with curated set of test photos and manual test checklist.
**Rationale:** Real-world testing catches issues automated tests miss. Acceptable for single-user MVP.
**Impact:** Create test photo set and manual test checklist before release.

### D-DES-012: Macro Totals Storage
**Date:** 2026-02-04
**Updated:** 2026-02-05
**Question:** Should totalCarbs/totalProtein/totalFat be stored or calculated on read?
**Decision:** Store totals with the meal record. Totals are immutable once saved.
**Rationale:** Meal records are the authoritative source of macro data. The image is just a tool to generate macro estimates - the stored numbers are what matter. Totals are calculated before save and stored as part of the immutable record.
**Impact:** Meal schema includes totalCarbs, totalProtein, totalFat fields. Calculated once before save, stored permanently.

### D-DES-013: AI Timeout Behaviour
**Date:** 2026-02-05
**Question:** What happens when AI recognition times out at 10 seconds?
**Decision:** Cancel request immediately and show error with "Try Again" and "Enter Manually" options.
**Rationale:** User should have control over retry vs fallback. Don't leave user waiting indefinitely.
**Impact:** AI service must implement 10-second timeout. UI shows two-button error state.

### D-DES-014: Quantity/Unit Discarding
**Date:** 2026-02-05
**Question:** Should AI-returned quantity and unit fields be preserved in stored meals?
**Decision:** Discard quantity and unit. Store only name + macros.
**Rationale:** The macro values (carbs, protein, fat in grams) are what matter for diabetes management. Quantity/unit are intermediate values used by AI for estimation but not needed in the stored record.
**Impact:** FoodItem type only has name + macros. RecognisedFoodItem has quantity/unit but these are not persisted.

### D-DES-015: Partial Failure Handling
**Date:** 2026-02-05
**Question:** What happens when image upload succeeds but meal save fails?
**Decision:** Orphaned images in blob storage are acceptable. Log the failure and let TTL clean up.
**Rationale:** Image retention is nice-to-have, not need-to-have. The 30-day TTL will clean up orphans. Adding transactional rollback adds complexity without significant benefit.
**Impact:** No rollback mechanism needed. Server-side logging for monitoring orphaned images.

---

## Architecture Decisions

See `plan.md` Section 4 for technical decisions (D1-D9) covering:
- Framework choice (SvelteKit + Svelte 5)
- TypeScript strict mode
- Azure Cosmos DB
- Azure Blob Storage
- Zod validation
- Multi-provider AI architecture
- mmol/L only for BSL
- Repository pattern
- Irish English localisation
