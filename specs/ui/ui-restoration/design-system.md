# MeData Design System (Figma Archive)

**Version:** 0.2
**Date:** 2026-06-08
**Status:** Draft — full component catalogue (§3), icon suite (§7), and animation catalogue (§8) authored as the Figma-archive source of truth. See [`decision_log.md`](./decision_log.md).

This document is the canonical source of truth for the MeData visual identity. The pre-refocus code at commit `3b5d54d` implements the values defined here (read it via `git show 3b5d54d:<path>`); the Figma file authored via the Claude `/figma` plugin is downstream. Drift is reconciled by re-running the plugin from code, not by editing code from Figma. See `decision_log.md` Decisions 1–2.

---

## 1. Brand Tokens

### 1.1 Colour Tokens

| Token | Value | Use |
|---|---|---|
| `--color-brand-accent` | `#63ff00` | Primary brand accent. Logo default-variant stroke, primary CTA, active nav, theme-color meta. |
| `--color-brand-bg` | `#064e3b` | Brand-tinted background (dark green). Reserved; not currently a primary surface. |
| `--color-primary-background` | `#0a0a0a` | App background. The `body`/`html` default. |

> **Token naming note:** the pre-refocus `app.css` `@theme` block defines only two custom tokens — `--color-brand-accent` (`#63ff00`) and `--color-brand-bg` (`#064e3b`). Earlier drafts of this document referred to the latter as `--color-brand-background`; the code name `--color-brand-bg` is authoritative. The `#0a0a0a` app background is the literal value used in raster exports (§6); it is not a named `@theme` token in code.

### 1.1a Greyscale and Semantic Palette (Tailwind defaults)

The components do not define their own grey/red scales — they use Tailwind's default palette via utility classes. The Figma archive SHOULD create variables for the specific steps the suite actually references, so component fills/strokes bind to tokens rather than hex literals:

| Token (Tailwind default) | Value | Used by |
|---|---|---|
| `gray-950` | `#030712` | Button focus-ring offset, `BottomNav` background (`/95`) |
| `gray-900` | `#111827` | `StorageError` background, `ExpandableSection` surface (`/50`) |
| `gray-800` | `#1f2937` | Input background, secondary button, card surfaces, borders |
| `gray-700` | `#374151` | Borders, secondary-button hover |
| `gray-500` | `#6b7280` | Input placeholder, EmptyState icon |
| `gray-400` | `#9ca3af` | Muted text, inactive nav/icon |
| `gray-200` | `#e5e7eb` | Headings on dark surfaces |
| `gray-100` | `#f3f4f6` | Secondary-button text |
| `red-500` | `#ef4444` | Input error border, error icon background (`/20`) |
| `red-400` | `#f87171` | Input error text, error icon |

Values are Tailwind v4 defaults at time of snapshot; treat the table as the authoritative list of which steps the archive needs.

### 1.2 Typography

| Token | Value |
|---|---|
| Font family | System default (`-apple-system`, `BlinkMacSystemFont`, `Segoe UI`, `Roboto`, sans-serif via Tailwind's default sans stack). No custom web fonts loaded. |
| Scale | Tailwind's default scale (`text-sm` 14px, `text-base` 16px, `text-lg` 18px, `text-xl` 20px, `text-2xl` 24px). |

If a custom font is introduced later, it must be added to this section and to the design-system Figma file in lockstep.

---

## 2. Logo

### 2.1 Logo Path

The MeData glyph is a single SVG at `viewBox="0 0 128 128"` composed of three sub-paths drawn with `stroke-width="24"`, `stroke-linecap="round"`, `stroke-linejoin="round"`, and `fill="none"`.

| Sub-path | `d` attribute | Inline `stroke-dasharray` |
|---|---|---|
| Main curve + left vertical | `M 24,24 C 130,24 130,104 24,104 L 24,64` | `256` (drives animation per §2.3) |
| Right vertical | `M 104,64 L 104,104` | `40` (drives animation per §2.3) |
| Centre dot (zero-length line rendered as round-cap dot) | `M 64,64 L 64,64` | `0.01` (forces the round-cap dot to render; the dot is animated via `opacity`, not `stroke-dashoffset` — see §2.3) |

### 2.2 Logo Variants

| Variant | Main stroke | Centre dot stroke | Notes |
|---|---|---|---|
| `default` | `#63ff00` | `#63ff00` | Brand accent on both. |
| `contrast` | `#000000` | `#ffcc00` | High-contrast variant for light backgrounds or accessibility. |
| `colour` | `url(#colour-gradient)` | `url(#colour-gradient)` | Rainbow linear gradient (left-to-right). Apple-touch-icon counterpart file is `apple-touch-icon-colour.png`. |

The `colour` variant gradient stops (linearGradient `x1=0% y1=0% x2=100% y2=0%`):

| Offset | Stop colour |
|---|---|
| `0%` | `#E40303` |
| `20%` | `#FF8C00` |
| `40%` | `#FFED00` |
| `60%` | `#008026` |
| `80%` | `#24408E` |
| `100%` | `#732982` |

### 2.3 Logo Animation

The animated Logo draws and undraws the three sub-paths in a 3-second infinite loop using `stroke-dashoffset` on the curve and right vertical, and `opacity` on the centre dot.

Total duration: `3s`. Timing function: `ease-in-out`. Iteration: `infinite`.

**Main curve keyframes** (initial `stroke-dashoffset: 256`):

| Time | `stroke-dashoffset` |
|---|---|
| `0%` | `256` |
| `35%`–`65%` | `0` (fully drawn) |
| `100%` | `256` (fully undrawn) |

**Right vertical keyframes** (initial `stroke-dashoffset: 40`):

| Time | `stroke-dashoffset` |
|---|---|
| `0%`–`15%` | `40` |
| `42%`–`58%` | `0` |
| `85%`–`100%` | `40` |

**Centre dot keyframes** (uses `opacity`, not `stroke-dashoffset`):

| Time | `opacity` |
|---|---|
| `0%`–`30%` | `0` |
| `35%`–`65%` | `1` |
| `70%`–`100%` | `0` |

**Reduced-motion behaviour:** when `prefers-reduced-motion: reduce`, the Logo renders the static end-state (all three sub-paths fully drawn, dot fully visible) with no animation classes applied. See §4 for SSR direction.

### 2.4 Logo Sizes

| Size token | Rendered pixel dimensions | Use |
|---|---|---|
| `sm` | 16 × 16 | Inline favicon-sized contexts. |
| `md` | 32 × 32 | AppShell header (default). |
| `lg` | 48 × 48 | Reserved for future loading affordances (see §3 `LogoLoader` pattern). |
| `splash` | 96 × 96 | Reserved for future splash / hero contexts. Not currently wired. |

### 2.5 Logo Accessibility

`role="img"` and `aria-label="MeData logo"` are required on every Logo render. The `aria-label` value is fixed; do not parameterise.

---

## 3. Component Catalogue

These components exist in the pre-refocus snapshot (`3b5d54d`). None are restored as code (decision_log Decision 3); each is authored as a Figma component (variant set) from the specs below. Animation behaviour is summarised here and specified in full in §8. Colours reference the tokens in §1.

### 3.1 Button

Source: `src/lib/components/ui/Button.svelte`.

| Prop | Values | Default |
|---|---|---|
| `variant` | `primary`, `secondary`, `ghost` | `primary` |
| `size` | `sm`, `md`, `lg` | `md` |
| `animation` | `none`, `subtle`, `full` | `subtle` |
| `loading` | boolean | `false` |
| `disabled` | boolean | `false` |
| `href` | string (renders `<a role="button">` instead of `<button>`) | — |

**Variant styles** (base: `inline-flex`, `font-medium`, `rounded-lg`, `transition-colors` 200ms, focus ring 2px offset on `gray-950`):

| Variant | Fill | Text | Hover | Border |
|---|---|---|---|---|
| `primary` | `brand-accent` (`#63ff00`) | `gray-950` | fill `brand-accent/90` | — |
| `secondary` | `gray-800` | `gray-100` | fill `gray-700` | `gray-700` |
| `ghost` | transparent | `gray-300` | bg `gray-800`, text white | — |

**Sizes:** `sm` = `text-sm`, `px-3 py-1.5`, min-height 32px · `md` = `text-base`, `px-4 py-2`, min-height 44px · `lg` = `text-lg`, `px-6 py-3`, min-height 52px.

**States to author as Figma variants:** default, hover, pressed, loading (leading 16px spinner, `animate-spin`), disabled (opacity 50%, not-allowed). Press/ripple/shimmer motion is in §8.2.

### 3.2 Input

Source: `src/lib/components/ui/Input.svelte`.

| Prop | Values | Default |
|---|---|---|
| `type` | `text`, `email`, `password`, `tel`, `url`, `search`, `number` | `text` |
| `label` | string (floating label) | — |
| `placeholder` | string (shown only while floating) | — |
| `required` / `disabled` | boolean | `false` |
| `error` | string (error message + error styling) | — |

**Base:** `w-full`, `px-4 py-3`, `text-base`, `rounded-lg`, `border`, `transition-all` 200ms, fill `gray-800`, text white, 2px focus ring.

**State styling:**

| State | Border | Focus ring | Label colour |
|---|---|---|---|
| default | `gray-700` | `brand-accent/30`, border `brand-accent` | `gray-400` |
| focused | `brand-accent` | `brand-accent/30` | `brand-accent` |
| error | `red-500` | `red-500/30`, border `red-400` | `red-400` (+ `red-400` message below) |
| disabled | `gray-700` | — | opacity 50% |

**Floating label:** rests vertically centred at `text-base`; when focused OR value non-empty it moves to `-top-2.5` at `text-xs font-medium` with a `gray-800` background chip. Placeholder is hidden until the label has floated. Focus-shimmer underline in §8.3.

### 3.3 EmptyState

Source: `src/lib/components/ui/EmptyState.svelte`. No animation.

| Prop | Type |
|---|---|
| `title` | string (required) — `text-lg font-medium`, `gray-200` |
| `description` | string — `text-sm`, `gray-400`, `max-w-sm` |
| `icon` | slot/snippet — `gray-500`, centred above title |
| `action` | slot/snippet — below, `mt-6` |

Layout: centred column, `py-12 px-4`, text-centre.

### 3.4 ExpandableSection

Source: `src/lib/components/ui/ExpandableSection.svelte`.

| Prop | Type | Default |
|---|---|---|
| `title` | string | — |
| `subtitle` | string | — |
| `collapsed` | boolean | `true` |

Surface: `rounded-lg`, `border gray-800`, fill `gray-900/50`. Header is a button row (`title` `text-lg font-semibold gray-200`, optional `subtitle` `text-sm gray-400`) with a trailing chevron (`h-5 w-5`, chevron-down path). Author Figma variants: **collapsed** (chevron 0°) and **expanded** (chevron 180°, body panel visible with top border). Chevron spring rotation + body slide in §8.4.

### 3.5 LoadingSpinner

Source: `src/lib/components/ui/LoadingSpinner.svelte`.

| Prop | Values | Default |
|---|---|---|
| `size` | `sm` (16px), `md` (32px), `lg` (48px) | `md` |

Circular outline: `rounded-full`, `border-2`, `border-current`, top border transparent, colour `brand-accent`, `animate-spin`. `role="status"`, `aria-label="Loading"`. Rotation in §8.5.

### 3.6 StorageError

Source: `src/lib/components/ui/StorageError.svelte`. Full-screen fallback, no animation (uses `transition-colors` on its retry button only).

- Full-screen centred column, fill `gray-900`, `p-6`.
- Warning icon (`h-12 w-12`, `red-400`) in a `red-500/20` circular badge.
- Title "Storage Unavailable" (`text-xl font-bold` white); body copy `gray-400 max-w-md`.
- "Common causes" list panel (`gray-800` surface) and a monospace error panel (`gray-800/50`, `gray-500`) showing the `error` prop.
- Actions: primary "Try Again" button (`brand-accent` fill, `gray-900` text, `transition-colors`) and a troubleshooting link.

### 3.7 LogoLoader (pattern, not a discrete component)

A wrapping pattern that uses an animated `Logo` at `size="lg"` (48px) as a loading affordance, with a 200ms show-after delay and a 600ms minimum display once shown. Not present as a standalone file in the snapshot; documented for completeness and authored in Figma as a single frame using the animated Logo end-state.

---

## 4. SSR and Hydration Direction

Server-rendered HTML contains the Logo in its static end-state with no animation classes or `style` attributes that produce motion. The client, after hydration, conditionally adds animation classes only when `animated={true}` AND `window.matchMedia('(prefers-reduced-motion: reduce)').matches === false`.

This means the SSR HTML is identical for users with and without reduced-motion. The `getAnimationDuration(durationMs)` utility's SSR return value (the supplied `durationMs`) is consequently not what suppresses Logo animation under SSR — the Logo component's own conditional rendering does that. The utility's SSR value is used by client-only call-sites that need a sensible default before they can read the media query.

---

## 5. Variant Naming

The Logo's `variant` prop accepts `default`, `contrast`, and `colour`. The apple-touch-icon files mirror this naming: `apple-touch-icon-default.png`, `apple-touch-icon-contrast.png`, `apple-touch-icon-colour.png`. The pre-refocus codebase named the third asset `apple-touch-icon-pride.png`; that name is **not** restored — the new name aligns with the `variant` prop value.

---

## 6. Raster Export Specs

The raster PNG icons (`apple-touch-icon-*.png` and `icon-192.png`/`icon-512.png`) are exported from the canonical SVG at the dimensions and background settings below.

### 6.1 Apple Touch Icons (180×180)

| Asset | Dimensions | Background fill | Foreground |
|---|---|---|---|
| `apple-touch-icon-default.png` | 180×180 | `#0a0a0a` (matches `--color-primary-background`) | Default-variant glyph (stroke `#63ff00` on both main and dot) |
| `apple-touch-icon-contrast.png` | 180×180 | `#ffffff` | Contrast-variant glyph (main stroke `#000000`, dot stroke `#ffcc00`) |
| `apple-touch-icon-colour.png` | 180×180 | `#0a0a0a` | Colour-variant glyph (rainbow gradient stroke per §2.2 on both main and dot) |

A solid background is required for apple-touch-icons because iOS composites them on the home screen and does not provide its own backing fill. Transparent backgrounds would render against an unpredictable system colour.

### 6.2 PWA Manifest Icons (`any` and `maskable`)

| Asset | Dimensions | Background fill | Foreground | Notes |
|---|---|---|---|---|
| `icon-192.png` | 192×192 | `#0a0a0a` | Default-variant glyph | `purpose: "any"` manifest entry. |
| `icon-512.png` | 512×512 | `#0a0a0a` | Default-variant glyph centred within the inner 80% safe zone | Single asset listed twice in the manifest: once as `purpose: "any"`, once as `purpose: "maskable"`. The 80% safe-zone constraint ensures Android adaptive-icon cropping does not clip the glyph. |

The glyph in `icon-512.png` MUST be scaled such that the bounding box of all three sub-paths fits within a centred 80% square (i.e. 410×410 within the 512×512 canvas, with 51px padding on all sides). The same scaling is applied to `icon-192.png` (centred 154×154 within a 192×192 canvas) to keep the two manifest icons visually consistent.

---

## 7. Icon Suite

All icons share one drawing convention: `viewBox="0 0 24 24"`, `fill="none"`, `stroke="currentColor"`, default rendered size `h-6 w-6` (24×24). Colour is inherited from context (`currentColor`) — in Figma, author them with a bound stroke variable (default `gray-400`, active `brand-accent`) rather than a baked colour. `aria-hidden="true"`.

### 7.1 Macro / Drink Icons

Source: `src/lib/components/icons/`. Seven single-purpose nutrition icons. Each `d` value below is the authoritative path data.

| Icon | Glyph | Path `d` (stroke-width unless noted = 2) |
|---|---|---|
| `AlcoholIcon` | Wine glass | bowl `M8 3h8l-1 8a4 4 0 01-3 3.87V18`; level `M9 7h6` (sw 1.5); stem `M12 15v3`; base `M8 21h8` |
| `BSLIcon` | Blood drop | drop `M12 3c-3.5 4.5-6 7.5-6 11a6 6 0 1012 0c0-3.5-2.5-6.5-6-11z`; reading lines `M9 13h6M9 16h4` |
| `CarbsIcon` | Bread loaf | loaf `M4 12c0-3 2-5 8-5s8 2 8 5v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5z`; crust `M7 10c2-1 8-1 10 0`; slices `M9 12v5M12 12v5M15 12v5` (sw 1.5) |
| `FatIcon` | Oil drop | drop `M12 3c-4 5-7 8-7 12a7 7 0 1014 0c0-4-3-7-7-12z`; shine `M9 14c0-1.5 1-3 3-4` (sw 1.5) |
| `InsulinIcon` | Syringe | tip `M4 20l3-3`; barrel `rect x7 y7 w10 h6 rx1 rotate(45 12 10)`; plunger `M17 7l3-3M18.5 5.5l1.5-1.5`; marks `M10 11l1-1M12 13l1-1` (sw 1.5) |
| `MealIcon` | Open book | `M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253` |
| `ProteinIcon` | Drumstick | meat `M15.5 4.5a4 4 0 00-5.66 5.66l-5.66 5.66a2 2 0 102.83 2.83l5.66-5.66a4 4 0 005.66-5.66`; bone end `circle cx17 cy7 r1.5` |

All round line-caps and joins (`stroke-linecap="round"`, `stroke-linejoin="round"`) except the plain reading/slice/measurement lines, which set only `stroke-linecap="round"`.

### 7.2 Navigation Icons

Source: inlined in `src/lib/components/layout/BottomNav.svelte` (not separate files). Same convention as §7.1. Four icons, selected by `icon` key:

| Key | Glyph | Path `d` (stroke-width 2, round caps/joins) |
|---|---|---|
| `home` | House | `M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6` |
| `plus-circle` | Add | `M12 9v3m0 0v3m0-3h3m-3 0H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z` |
| `list` | List | `M4 6h16M4 10h16M4 14h16M4 18h16` |
| `settings` | Gear | gear `M10.325 4.317c.426-1.756 2.924-1.756 3.35 0 …` (full Heroicons cog path); centre `M15 12a3 3 0 11-6 0 3 3 0 016 0z` |

`BottomNav` itself: fixed bottom bar, `border-t gray-800`, fill `gray-950/95`, backdrop blur, safe-area bottom padding; each tab min 56×64px, label `text-xs` `mt-1`; active tab `brand-accent`, inactive `gray-400` (hover `gray-200`), `aria-current="page"` on the active item.

---

## 8. Animation Catalogue

Exact, reproducible specifications for every animation in the snapshot. Per `decision_log.md` Decision 7, these are the source of truth; the Figma file approximates them with Smart Animate / variant states where feasible and leaves the rest documented-only here. All animations are suppressed under `prefers-reduced-motion: reduce` (via `svelte/motion`'s `prefersReducedMotion` or a media query) — the reduced-motion end-state is noted per entry.

### 8.1 Logo draw/undraw loop

Specified in full in §2.3 (3s `ease-in-out` infinite loop; `stroke-dashoffset` on curve + right vertical, `opacity` on the centre dot). Reduced-motion: static fully-drawn end-state.

### 8.2 Button — press, ripple, shimmer, shadow

Source: `Button.svelte`. Gated by the `animation` prop (`none` disables all; `subtle` enables press + ripple + shadow-hover; `full` adds shimmer + content scale). All suppressed under reduced motion.

| Effect | Spec |
|---|---|
| Press scale | Svelte `Spring` (stiffness 0.3, damping 0.8) on `transform: scale()`; pointer-down → `0.97`, pointer-up/leave → `1`. |
| Ripple | On pointer-down, a circle (20px, `rgba(255,255,255,0.4)`; primary variant `rgba(0,0,0,0.15)`) spawns at the pointer; `Spring` (stiffness 0.15, damping 0.9) scales 0→20 with opacity `1 − scale/20`; removed after 600ms; enter `transition: scale 300ms cubicOut`. |
| Shadow-hover (`subtle`+) | `box-shadow` `0 4px 12px rgba(0,0,0,.15), 0 2px 4px rgba(0,0,0,.1)` on hover; transition 200ms `cubic-bezier(0.33,1,0.68,1)`. |
| Shadow-hover (`full`) | `0 8px 24px rgba(0,0,0,.2), 0 4px 8px rgba(0,0,0,.15)`; inner content scales to `1.02`. |
| Shimmer (`full`) | A 90° white gradient sweep (`rgba(255,255,255,0.3)`; secondary/ghost `0.12`) slides left:-100%→100% over 400ms `cubic-bezier(0.33,1,0.68,1)` on hover. |

Reduced-motion: all transitions removed, shimmer and ripple hidden, content scale reset.

### 8.3 Input — floating label + focus shimmer

Source: `Input.svelte`. Label transition `all 200ms ease-out` between resting and floated positions (§3.2). Focus-shimmer: a 2px underline gradient (`transparent → brand-accent → transparent`) grows `width 0 → 100%` over 300ms `ease` on `:focus-within`. Reduced-motion: label and underline transitions removed (states still apply, just instant).

### 8.4 ExpandableSection — chevron rotation + body slide

Source: `ExpandableSection.svelte`. Chevron rotation via `Spring` (stiffness 0.3, damping 0.8) 0°↔180°. Body reveal via Svelte `slide` transition, duration `getAnimationDuration(200)` (200ms, or 0 under reduced motion). Reduced-motion: chevron snaps (`hard`) and slide duration is 0.

### 8.5 LoadingSpinner / Button spinner — rotation

Tailwind `animate-spin` (continuous 360° linear, 1s default). Reduced-motion is the call-site's responsibility (the home-page loader is gated per requirements §5.2); the component itself does not self-suppress.

### 8.6 PageTransition — route fade / slide

Source: `layout/PageTransition.svelte`. Keyed on `page.url.pathname`; direction from `navigationStore`.

| Direction | Keyframes |
|---|---|
| default (fade) | `fadeIn` 0.2s `ease-out`: opacity 0 → 1 |
| forward (`slide-left`) | `slideInFromRight` 0.25s `ease-out`: opacity 0 + `translateX(30px)` → opacity 1 + `translateX(0)` |
| back (`slide-right`) | `slideInFromLeft` 0.25s `ease-out`: opacity 0 + `translateX(-30px)` → opacity 1 + `translateX(0)` |

Reduced-motion: not internally guarded in the snapshot; the Figma archive documents the static end-state (fully opaque, untranslated).

### 8.7 Motion utility

`getAnimationDuration(durationMs)` (`src/lib/utils/motion.svelte.ts`) returns `0` when `prefersReducedMotion.current` is true, else `durationMs`. It is the single gate call-sites use to honour the user's reduced-motion preference. (SSR/direction nuance in §4.)
