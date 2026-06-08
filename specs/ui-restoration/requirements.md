# UI Restoration — Requirements (Figma Archive)

**Version:** 1.0
**Date:** 2026-06-08
**Status:** Draft
**Branch:** ui-archive

## Introduction

The MVP refocus commit (`d062061`) simplified the SvelteKit app and removed the MeData design system: the animated multi-variant `Logo`, the `prefers-reduced-motion` motion utility, a 7-icon macro/drink suite, the `BottomNav` navigation icons, the UI primitives (`Button`, `Input`, `EmptyState`, `ExpandableSection`, `LoadingSpinner`, `StorageError`), the `PageTransition` route animations, and several brand assets.

This spec **archives** that design system into a Figma file authored with the Claude `/figma` plugin toolset. It does **not** restore any of it as code. The source of truth is the pre-refocus snapshot at commit `3b5d54d` (read via git history) and the `design-system.md` document in this folder, which inventories every token, component, icon, and animation. The Figma file is a downstream, browsable representation that is reconciled by re-running the plugin from code. See [`decision_log.md`](./decision_log.md) for the decisions behind this framing.

The canonical visual values referenced by the acceptance criteria below — Logo SVG path data, variant colours, icon path data, component specs, and animation keyframes — live in [`design-system.md`](./design-system.md).

## Source of Truth

- **Code snapshot:** commit `3b5d54d`. Read sources with `git show 3b5d54d:<path>`; nothing is restored to the working tree (decision_log Decision 3).
- **Specification:** `design-system.md` in this folder.
- **Downstream:** the Figma file. Drift is reconciled by re-authoring from code, never the reverse (decision_log Decision 1).

## Non-Goals

- **Restoring any design-system code to the working tree.** No `Logo.svelte`, `motion.svelte.ts`, icons, primitives, or static assets are re-added. The MVP working tree is untouched (decision_log Decision 3).
- Restoring deleted application routes (auth, settings, log/import, history, validation) or any non-design-system code.
- Cross-platform (iOS/Android) implementations of any component.
- Pixel-exact reproduction of spring-physics or custom-keyframe animation inside Figma. Exact timings live in `design-system.md` §8; Figma approximates them (decision_log Decision 7).
- Building a runnable Figma prototype / clickable flow beyond the per-component interaction states described in Requirement 6.
- Carrying forward the `pride` asset filename; the variant is named `colour` everywhere (decision_log Decision 6).

## Requirements

### 1. Design System Inventory Completeness

**User Story:** As the person authoring the Figma file, I want a single document that fully inventories the code-side design system, so that the Figma file can be authored from a definitive source without reading the code directly.

**Acceptance Criteria:**

1. <a name="1.1"></a>`design-system.md` SHALL document, as the canonical source of truth: the brand colour tokens and the greyscale/semantic palette steps the suite uses (§1), the Logo path data, variants, animation, and sizes (§2), the full component catalogue (§3), the raster export specs (§6), the icon suite path data (§7), and the animation catalogue (§8).
2. <a name="1.2"></a>For each component in the catalogue (`Button`, `Input`, `EmptyState`, `ExpandableSection`, `LoadingSpinner`, `StorageError`, and the `LogoLoader` pattern), `design-system.md` §3 SHALL state its props, variants, sizes, states, and animation behaviour.
3. <a name="1.3"></a>`design-system.md` SHALL state that code (commit `3b5d54d`) is the source of truth and the Figma file is downstream, reconciled by re-running the plugin from code.

### 2. Figma Foundations (Variables and Styles)

**User Story:** As a consumer of the Figma file, I want colours, spacing, and type defined as Figma variables and styles, so that components reference tokens rather than hard-coded values and the file stays linked to the design system.

**Acceptance Criteria:**

1. <a name="2.1"></a>The Figma file SHALL define colour variables for the brand tokens (`brand-accent` `#63ff00`, `brand-bg` `#064e3b`) and for each greyscale/semantic step listed in `design-system.md` §1.1a that the components reference.
2. <a name="2.2"></a>The Figma file SHALL define text styles matching the typography scale in `design-system.md` §1.2 (Tailwind default sans stack; `text-sm`/`base`/`lg`/`xl`/`2xl`).
3. <a name="2.3"></a>Component fills, strokes, and text in the Figma file SHALL bind to these variables/styles rather than literal hex values, wherever a corresponding token exists.

### 3. Figma Logo Component

**User Story:** As a designer, I want the MeData Logo as a Figma component with its variants and sizes, so that the brand mark is reusable and consistent.

**Acceptance Criteria:**

1. <a name="3.1"></a>The Figma file SHALL contain a `Logo` component built from the SVG path data, `viewBox`, stroke width, and line caps/joins in `design-system.md` §2.1.
2. <a name="3.2"></a>The `Logo` component SHALL provide the three variants `default`, `contrast`, and `colour` with the stroke values and gradient stops in `design-system.md` §2.2 (the `colour` variant using the rainbow linear gradient).
3. <a name="3.3"></a>The `Logo` component SHALL provide the four sizes `sm` (16), `md` (32), `lg` (48), `splash` (96) per `design-system.md` §2.4.
4. <a name="3.4"></a>The Logo's animated state SHALL be represented per Requirement 6, with its static fully-drawn end-state authored as the default.

### 4. Figma Icon Suite

**User Story:** As a designer, I want the nutrition and navigation icons as Figma components, so that the icon language is browsable and reusable.

**Acceptance Criteria:**

1. <a name="4.1"></a>The Figma file SHALL contain the seven macro/drink icons (`Alcohol`, `BSL`, `Carbs`, `Fat`, `Insulin`, `Meal`, `Protein`) built from the path data in `design-system.md` §7.1, on a 24×24 frame with round caps/joins as specified.
2. <a name="4.2"></a>The Figma file SHALL contain the four navigation icons (`home`, `plus-circle`, `list`, `settings`) from `design-system.md` §7.2.
3. <a name="4.3"></a>Icon strokes SHALL bind to a colour variable (default `gray-400`, with an active `brand-accent` state available) rather than a baked colour, mirroring the `currentColor` convention.

### 5. Figma UI Primitive Components

**User Story:** As a designer, I want the UI primitives as Figma component variant sets, so that the interaction states of the system are documented and reusable.

**Acceptance Criteria:**

1. <a name="5.1"></a>The Figma file SHALL contain a `Button` variant set covering `variant` (`primary`/`secondary`/`ghost`) × `size` (`sm`/`md`/`lg`) and the states default/hover/pressed/loading/disabled, with fills, text, borders, and sizing per `design-system.md` §3.1.
2. <a name="5.2"></a>The Figma file SHALL contain an `Input` component with default/focused/error/disabled states and the floating-label behaviour per `design-system.md` §3.2.
3. <a name="5.3"></a>The Figma file SHALL contain `EmptyState`, `ExpandableSection` (collapsed + expanded variants), `LoadingSpinner` (sm/md/lg), and `StorageError` per `design-system.md` §3.3–§3.6.
4. <a name="5.4"></a>Component text, fills, and strokes SHALL bind to the variables and styles from Requirement 2 wherever a token exists.

### 6. Animation Representation

**User Story:** As a consumer of the archive, I want the system's animations represented in Figma where feasible and exactly specified in the document otherwise, so that the interaction design is preserved.

**Acceptance Criteria:**

1. <a name="6.1"></a>For each animation in `design-system.md` §8 (Logo loop, Button press/ripple/shimmer/shadow, Input float-label/focus-shimmer, ExpandableSection chevron/slide, spinner rotation, PageTransition fade/slide), the Figma file SHALL author the relevant end-states as component variants (e.g. default/hover/pressed, collapsed/expanded).
2. <a name="6.2"></a>WHERE the Figma Plugin API supports a faithful-enough approximation, the transition between states SHALL be authored as a Smart Animate / prototype interaction; WHERE it does not (spring physics, custom keyframes), the motion SHALL be left documented-only in `design-system.md` §8 and SHALL NOT be misrepresented in Figma.
3. <a name="6.3"></a>Every animation entry's reduced-motion end-state, as noted in `design-system.md` §8, SHALL be the authored default state of the corresponding Figma component.

### 7. Authoring Fidelity and Verification

**User Story:** As a maintainer, I want the authored Figma file checked against the source, so that the archive is accurate.

**Acceptance Criteria:**

1. <a name="7.1"></a>The Figma file SHALL be authored with the Claude `/figma` plugin skills (`figma-generate-library` for foundations and components; `figma-generate-design` for any composed example screens).
2. <a name="7.2"></a>Each authored section (foundations, Logo, icon suite, primitives) SHALL be visually verified against `design-system.md` via Figma screenshots, checking for clipped text, wrong variants, placeholder text, and incorrect colours before the section is considered complete.
3. <a name="7.3"></a>The third variant SHALL be named `colour` in the Figma file (not `pride`), matching the `Logo` variant value and the `apple-touch-icon-colour.png` asset name (decision_log Decision 6).

### 8. Raster Asset Reference

**User Story:** As someone exporting home-screen/PWA icons later, I want the raster export specs preserved, so that the icon assets can be regenerated consistently.

**Acceptance Criteria:**

1. <a name="8.1"></a>`design-system.md` §6 SHALL remain the authoritative spec for the raster exports (`apple-touch-icon-{default,contrast,colour}.png` at 180×180 and `icon-192.png`/`icon-512.png` with the 80% safe-zone), including background fills.
2. <a name="8.2"></a>This spec SHALL NOT generate or commit the raster PNGs; §6 is reference material for a future export step.
