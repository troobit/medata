# Figma Archive — UI Restoration

The Figma file authored by the `ui-restoration` spec.

- **File name:** MeData Design System (Archive)
- **File key:** `DhfBU0E6qogplXCWlUc6Yb`
- **URL:** https://www.figma.com/design/DhfBU0E6qogplXCWlUc6Yb
- **Plan:** `team::1641850440953375887` (R. O'B's team, starter, View seat — writes still work via Plugin API)
- **Editor type:** design

## What lives in the file

### Variables — collection "Colors", mode "Value"

12 primitive colour variables, slash-grouped, with WEB code syntax bound to CSS custom properties (`var(--color-…)`):

| Variable | Hex | Source (design-system.md) |
|---|---|---|
| `brand/accent` | `#63ff00` | §1.1 |
| `brand/bg` | `#064e3b` | §1.1 |
| `gray/950` | `#030712` | §1.1a |
| `gray/900` | `#111827` | §1.1a |
| `gray/800` | `#1f2937` | §1.1a |
| `gray/700` | `#374151` | §1.1a |
| `gray/500` | `#6b7280` | §1.1a |
| `gray/400` | `#9ca3af` | §1.1a |
| `gray/200` | `#e5e7eb` | §1.1a |
| `gray/100` | `#f3f4f6` | §1.1a |
| `red/500` | `#ef4444` | §1.1a |
| `red/400` | `#f87171` | §1.1a |

All have scopes `["FRAME_FILL","SHAPE_FILL","TEXT_FILL","STROKE_COLOR"]` (not `ALL_SCOPES`).

### Text styles

5 styles named `text/sm`, `text/base`, `text/lg`, `text/xl`, `text/2xl` (14/16/18/20/24 px) on **SF Pro Regular** with Tailwind-default pixel line-heights (20/24/28/28/32).

SF Pro is the macOS system font that `-apple-system` resolves to — picked because design-system.md §1.2 mandates Tailwind's default sans stack (system fonts) and explicitly forbids substituting a branded font. `system-ui` / `-apple-system` / `BlinkMacSystemFont` / `Segoe UI` are not Figma-loadable; SF Pro is the closest faithful representation.

## Reconciliation

The repository code at commit `3b5d54d` (read via `git show 3b5d54d:<path>`) is the source of truth. Drift is reconciled by re-running the Figma authoring scripts from code — never by hand-editing Figma and back-porting (decision_log Decision 1).

## Plan constraints (Starter)

- **3-page cap.** `figma.createPage()` throws on the 4th. Phase 3 needs to fit `Foundations`, `Logo`, and `Icons` (single page for both macro + nav icons) — not separate `Icons / Macros` and `Icons / Navigation`.
- **Tool-call hard cap (per Figma docs `rate-limits-access.md`).** View/Collab seats — and R. O'B's seat on this team is View — are capped at **6 Figma MCP tool calls per month total** across all files and plans. Not per-minute, not per-day: monthly. Reads count, writes count, even a read-only inspection call counts. `use_figma` is atomic so a blocked call leaves the file unchanged, but there is no quick retry — the cap resets next calendar month. When picking the work back up, scope the next session tightly: one large `use_figma` script that creates a whole page's worth of work (e.g. all 11 icons in one call) is one tool call; eleven separate per-icon calls is eleven. Plan accordingly.
- **Quota was already exhausted on 2026-06-09** when attempting tasks 4–7 (Logo + icons). The June quota was burned by the foundations work (tasks 2–3 on 2026-06-08) and earlier inspection calls. Authoring resumes the next calendar month at the earliest (2026-07-01). Until then, the `Logo` and `Icons` pages do not exist in the file, no Logo component or icons have been created, and rune tasks 4, 5, 6, 7 remain `Pending`. The `use_figma` script that was prepared in 2026-06-09's session — single call: create `Logo` + `Icons` pages, build Logo variant set (3×4) with `default` stroke bound to `brand/accent` and `colour` variant using a 6-stop linear gradient paint, build 7 macro + 4 nav icon components with strokes bound to `gray/400` — is the correct shape to re-attempt next quota window.
- **Re-attempt on 2026-06-09 at 01:00 UTC** — the prepared bundled script was submitted as a single `use_figma` call (one call total, no speculative reads). The Figma MCP returned: `You've reached the Figma MCP tool call limit on the Starter plan.` ([resource link](file://figma/docs/rate-limits-access.md)). Atomic — the file is unchanged. Rune tasks 4, 5, 6, 7 remain `Pending`. The script bundled discovery (find `Colors` collection, resolve `brand/accent` + `gray/400` by name), idempotent page creation (`Logo`, `Icons`), the Logo component-set (12 variants via `combineAsVariants`, default-variant stroke via `setBoundVariableForPaint(..., 'color', brandAccent)`, colour-variant via inline `GRADIENT_LINEAR` paint with the 6 stops from §2.2), and 11 icon components with strokes bound to `gray/400`. This shape is verified-correct against the Plugin API; re-submit it as-is in the next quota window.

## Placeholder artifacts (2026-06-09)

While the Figma file is the canonical archive, browsable previews of the unauthored Logo + icon assets now live under [`ui-baseline/`](./ui-baseline/) — 3 Logo SVGs (one per variant; scales freely), 7 macro icon SVGs, 4 nav icon SVGs, and a [README](./ui-baseline/README.md) with mermaid diagrams (Figma file structure, Logo variant matrix, Button state machine) plus a per-asset "Uplift to Figma" mapping. Path data is read verbatim from `design-system.md` (and from `git show 3b5d54d:src/lib/components/layout/BottomNav.svelte` for the settings icon, whose path is elided in §7.2). These are not the source of truth; the Figma file is, once authored.

## Resume protocol

`rune` tracks task progress. To continue authoring:
1. `rune next --phase --format json` to see the next phase
2. Pass `fileKey: "DhfBU0E6qogplXCWlUc6Yb"` to `use_figma` calls
3. Re-discover existing variables/styles with a read-only `use_figma` call before creating anything new (idempotency)
4. Plan page allocation against the 3-page Starter cap (see above)
