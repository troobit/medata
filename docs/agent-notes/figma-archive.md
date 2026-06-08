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
- **Tool-call rate limit.** Figma MCP write calls are rate-capped on Starter; long phases hit the cap mid-flight and return `You've reached the Figma MCP tool call limit on the Starter plan.` `use_figma` is atomic, so a blocked call leaves the file unchanged — pick the work back up where it stopped on the next session.

## Resume protocol

`rune` tracks task progress. To continue authoring:
1. `rune next --phase --format json` to see the next phase
2. Pass `fileKey: "DhfBU0E6qogplXCWlUc6Yb"` to `use_figma` calls
3. Re-discover existing variables/styles with a read-only `use_figma` call before creating anything new (idempotency)
4. Plan page allocation against the 3-page Starter cap (see above)
