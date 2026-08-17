# Prerequisites: UI wireframe library

What must be true before and during this work. Not a task list — `tasks.md` owns sequencing.

## Toolchain — already in the repo, nothing new

- **`python3`, stdlib only**, for `tools/design_tokens/tokens_to_css.py`, run from the repository
  root exactly as the existing generators are (`tools/food_db/generate.py`: "Run from repo root:
  python3 tools/food_db/generate.py"). It must keep working on the stock macOS interpreter — this
  machine has Python 3.9.6.
- **`bash`** for `tools/check_surfaces.sh` via `make surfaces`, the same shape as `make spell` →
  `tools/check_spelling.sh`. System bash here is 3.2.57; the script must not need a newer one.
- **A browser** to view wireframes. They open as files and link only `../../tokens.css` and
  `../../wireframe.css`, fetching nothing else, so no local server is needed.
- **Xcode and the physical phone** for archive screenshots (below).

**No Node, no npm, no `node_modules`, no SaaS account.** If a step seems to need a package manager,
the step is wrong — except the one-off `web-v0` capture, which runs the SvelteKit toolchain that
already exists on `main` and leaves nothing behind on `research`.

## The expiring window — capture `web-v0` before `research` merges to `main`

A **dated risk that disappears silently**. `CLAUDE.md` says the cycle "currently runs along the
'research' branch, with intent to merge to main when the MVP work is done". `main` is still the
SvelteKit app at `adc3b56`, committed **2026-03-18**; its `package.json` asks for
`@sveltejs/kit ^2.15.0`, `vite ^6.0.0`, `svelte ^5.0.0`, which `pnpm-lock.yaml` resolved to 2.50.2,
6.4.1 and 5.49.2, while this machine has node v26.7.0 and pnpm 11.22.0 — nothing has verified that
install and dev server still resolve. Running it also wants backend configuration: `main`'s
`.env.example` lists `AZURE_COSMOS_CONNECTION_STRING` and `AZURE_BLOB_STORAGE_URL`, and
`RECOGNITION_MOCK_MODE=true` mocks recognition only, not persistence.

The Svelte source survives in git history at `adc3b56` either way. What expires is the ability to
**run** it and photograph the screens. If the window closes first, record those surfaces as
unarchivable rather than leaving `pending` rows that will never resolve.

## Screenshot capture — `ios-v0`

Needs the device named in `CLAUDE.md`: "Primary device: iPhone 16 Pro (devicectl id
`6AD781BA-89FF-5A82-A2A1-B5EC9469F465`, name `you`)", on the existing loop in
`docs/agent-notes/device-build-and-test.md` — `make deploy-device` for non-capture UI,
`make deploy-release-stub` for anything in the capture flow, since a Debug build cannot arm the
shutter. Match the launch `buildStamp` before trusting a frame.

**No scripted capture path exists and none is being built**; frames are taken at the phone and
copied off by hand, in the spirit of the attempt-tag convention — "Nothing reads any of it, no
tooling exists for it, and none should be built." Surfaces reachable only under the UI-test harness
cannot be photographed on a normal install; those rows carry `n/a`, not `pending`.

## Inputs that already exist

- `design-system/surfaces.md` — the catalogue, populated from the iOS surface inventory of `research`.
  The SvelteKit surfaces on `main` are archive input, not rows.
- `design-system/MASTER.md` and the **14** prose page files in `design-system/pages/`, frozen
  verbatim by the archive as `pages-v0/`.
- `design-system/wireframes/design-handoff-00/` — the prior handoff bundle, including the
  `MANIFEST.md` whose stale rows are cited as evidence.
- `specs/data/insulin-dosing/design-direction.md` (443 lines, `0baaea8`) — the worked example of
  maximally precise prose, and the evidence that even maximally precise prose cannot be pointed at.
  It briefed three options, which is the convention working; what it could not then do is name a
  region of one option so that a part of it could be taken into another.

## Constraints inherited

- **No new test target** — `CLAUDE.md`: "do not add new test scaffolding unless explicitly asked."
- **No tooling around git tags**, per the quote above from `docs/agent-notes/device-build-and-test.md`.
- **UK spelling**, gated by `make spell` — `CLAUDE.md`: "Always run `make spell` before committing
  docs or strings."
- **`App/` does not change.** `App/Colors.swift` stays hand-written and authoritative; the generator
  reads it and never writes it. A diff from this work touching `App/` is a defect.
- **`make surfaces` is green, and the ratchet is loaded**: `structs=61 missing=0`,
  `enum_cases=30 missing=0`, `covered=61 total=61 baseline=61`, `layer_violations=19 (report-only)`.
  The four defects its first run found — two `Shape` rows naming `MedataLoadingSymbol.*` where the
  declarations are `MedataSymbolGeometry.*`, and two `MealRoute` cases missing from any `state source`
  cell — are fixed in the catalogue, which is what earned `covered_min=61` in
  `tools/surfaces_baseline.txt`. Raise that number only when a real row raises `covered`; raising it to
  quiet a red check locks in a lie.

## Assumptions that would invalidate the design if false

1. **`App/Colors.swift` stays a flat list of `static let` colours in the forms the generator
   recognises.** It parses 22 today and exits non-zero on a form it cannot read. Colours computed in
   a view, or defined outside that one file, break the token rule and not just the script.
2. **Visual state stays expressed as named, closed enums.** The check reads cases out of Swift for
   the enums it is told about; state carried in loose booleans is invisible to it —
   `TiltGuideState` already reports `cases=0 note=namespace-enum`.
3. **Surfaces are designed one at a time and decided quickly.** Wireframes are maintenance-free only
   because they do not outlive their decision; several held open for weeks would rot exactly as the
   prose pages did.
4. **The `data` column stays documentation.** The layer report is advisory and lists 19 of the 22
   `App/*View.swift` and `App/*Sheet.swift` files today.
   If it ever gates the build, or anything generates code from that column, the premise that the
   catalogue adds no cross-layer dependency is gone.
