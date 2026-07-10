# User Input: CGM Connect

## Origin

This spec derives from the SNAQ input study (branch `snaqinput`, 2026-07-10). A collaborator's
app (SNAQ) was studied from 64 onboarding/UI screenshots; the flow map and gap analysis live in
`docs/agent-notes/snaq-flow-and-gap-analysis.md`. Gap #1 (glucose connection) is the headline
value item and became this spec.

## Mandate (user zone, `nextup.md`)

> The blood glucose connection via librelink and connected apps is of key value here. While
> taking screenshots of the images to import data are useful as an option, connecting directly
> ONCE then continuing to allow access removes another barrier to good data collection.

> The app ALSO includes warnings about it NOT being a medical device used for insulin dosing.
> THIS IS NOT how Medata works. It explicitly is designed to aid in reducing t1 diabetes
> patient mental load, so the suggestion is the point. This is being guided by professional
> medical researchers, so medical concern or suggestion is explicitly out of scope.

The app is for one person at this testing stage — excessive handholding in the UI is overkill.

## Decisions steered by the user (2026-07-10, AskUserQuestion)

- **Ingestion route:** build a connection-source abstraction and spike both routes, but assume
  **HealthKit as the primary, extensible path** — coverage grows as more CGMs write to Apple
  Health (e.g. FreeStyle Libre 3). The **LibreLinkUp follower "connect once"** pattern
  (SNAQ IMG_0629/0630) is the complement for devices that do not yet write to Health. The spec
  is explicitly expected to be iterated upon as device support expands.
- **Boundary:** this is the live-connection successor to `specs/data/libre-ingestion`
  (screenshot OCR), which listed CGM/HealthKit/third-party sync as a Non-Goal. Reference, don't
  duplicate; both write `bsl` events and coexist.
- **Folding:** every other SNAQ-derived piece routes elsewhere (favourites →
  `manual-carb-intake`; logbook/macros/shell → `home-router`; text-search = later spec;
  NL-Describe deferred, no-LLM invariant). This spec stays scoped to glucose ingestion.

## Constraints carried from CLAUDE.md

- No LLM and no network in the estimation path; a LibreLinkUp sync is ingestion, firewalled.
- Metric only — mmol/L, never mg/dL (convert on ingest).
- Developer-phase: no reassurance/disclaimer/consent copy.
- Irish/British spelling; verify with `make spell`.
</content>
