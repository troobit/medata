---
references:
    - specs/ui-restoration/requirements.md
    - specs/ui-restoration/design-system.md
    - specs/ui-restoration/decision_log.md
---
# UI Restoration (Figma Archive)

## Pre-Work

- [x] 1. Verify design-system.md inventory completeness <!-- id:uo74o2b -->
  - Read specs/ui-restoration/design-system.md and confirm every section the requirements depend on is present and accurate: §1 brand + greyscale/semantic palette, §2 Logo (paths, variants, animation, sizes), §3 component catalogue (Button, Input, EmptyState, ExpandableSection, LoadingSpinner, StorageError, LogoLoader pattern), §6 raster export specs, §7 icon suite path data, §8 animation catalogue.
  - Spot-check selected values (Logo viewBox 0 0 128 128, stroke-width 24, brand-accent #63ff00, brand-bg #064e3b, colour-gradient stops, icon viewBox 0 0 24 24) against `git show 3b5d54d:<path>` to confirm the document still matches the snapshot.
  - If any gap is found, update design-system.md before any authoring task begins. Do not restore code to the working tree.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)

## Foundations

- [ ] 2. Author Figma colour variables (brand + Tailwind steps) <!-- id:uo74o2c -->
  - Use the /figma-generate-library skill to create colour variables for brand-accent (#63ff00) and brand-bg (#064e3b).
  - Create variables for every Tailwind step listed in design-system.md §1.1a that components reference: gray-950, gray-900, gray-800, gray-700, gray-500, gray-400, gray-200, gray-100, red-500, red-400. Use the exact hex values from §1.1a.
  - Variable names should be stable and reusable (e.g. brand/accent, brand/bg, gray/950, red/500) so component fills can bind to them.
  - Blocked-by: uo74o2b (Verify design-system.md inventory completeness)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1)

- [ ] 3. Author Figma text styles for the typography scale <!-- id:uo74o2d -->
  - Create text styles for text-sm (14px), text-base (16px), text-lg (18px), text-xl (20px), text-2xl (24px), all using Tailwind's default sans stack (system fonts) per design-system.md §1.2.
  - No custom web font is loaded; do not substitute a branded font.
  - Blocked-by: uo74o2b (Verify design-system.md inventory completeness)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2)

## Logo & Icons

- [ ] 4. Author Logo component with variants and sizes <!-- id:uo74o2e -->
  - Use /figma-generate-library to build a Logo component from the three sub-paths in design-system.md §2.1, on viewBox 0 0 128 128 with stroke-width 24, stroke-linecap=round, stroke-linejoin=round, fill=none.
  - Variant prop: default (stroke #63ff00 on main + dot), contrast (main #000000, dot #ffcc00), colour (rainbow linearGradient with the six stops from §2.2 on both main and dot).
  - Size prop: sm 16, md 32, lg 48, splash 96.
  - Author the static fully-drawn end-state as the default state of every size×variant combination (matches the reduced-motion end-state). The animated representation is wired separately in the animation task.
  - Bind the default-variant stroke to the brand/accent colour variable from task 2; do not bake the hex value into the fill.
  - Apply role=img and aria-label='MeData logo' equivalents in Figma metadata where the plugin exposes them.
  - Blocked-by: uo74o2c (Author Figma colour variables (brand + Tailwind steps))
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4)

- [ ] 5. Author macro/drink icon components <!-- id:uo74o2f -->
  - Build the seven icons (Alcohol, BSL, Carbs, Fat, Insulin, Meal, Protein) from the path data in design-system.md §7.1 on a 24×24 frame with round caps/joins as specified per sub-path.
  - Bind the stroke to a colour variable (default gray-400, active brand-accent) rather than baking the colour — mirrors the currentColor convention.
  - aria-hidden=true equivalents on icons where the plugin exposes accessibility metadata.
  - Blocked-by: uo74o2c (Author Figma colour variables (brand + Tailwind steps))
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.3](requirements.md#4.3)

- [ ] 6. Author navigation icon components <!-- id:uo74o2g -->
  - Build the four navigation icons (home, plus-circle, list, settings) from the path data in design-system.md §7.2 on a 24×24 frame with stroke-width 2, round caps/joins.
  - Bind strokes to the same colour variable convention as task 5 (default gray-400, active brand-accent).
  - Do not author BottomNav itself in this task — only the four icons. BottomNav is a layout shell, not a documented UI primitive in §3.
  - Blocked-by: uo74o2c (Author Figma colour variables (brand + Tailwind steps))
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)

- [ ] 7. Verify foundations, Logo, and icons via screenshots <!-- id:uo74o2h -->
  - Use get_screenshot to capture the foundations page (variables + text styles), the Logo component with all three variants × four sizes, the seven macro/drink icons, and the four navigation icons.
  - Compare each against design-system.md: variable hex values match §1 and §1.1a, Logo path data and gradient stops match §2.1/§2.2, icon path data matches §7.1/§7.2.
  - Confirm the rainbow variant is labelled `colour` in the Figma variant value (not `pride`) per Requirement 7.3 and decision_log Decision 6.
  - Flag any clipped text, wrong variant, placeholder text, or incorrect colour and re-author before proceeding.
  - Blocked-by: uo74o2c (Author Figma colour variables (brand + Tailwind steps)), uo74o2d (Author Figma text styles for the typography scale), uo74o2e (Author Logo component with variants and sizes), uo74o2f (Author macro/drink icon components), uo74o2g (Author navigation icon components)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)

## UI Primitives

- [ ] 8. Author Button variant set with all states <!-- id:uo74o2i -->
  - Build the variant matrix variant (primary/secondary/ghost) × size (sm/md/lg) × state (default/hover/pressed/loading/disabled) per design-system.md §3.1.
  - Fills, text, borders, paddings, min-heights from §3.1. Bind fills/text to colour variables from task 2 and text styles from task 3.
  - Loading state includes a leading 16px spinner from the LoadingSpinner component (or an inline spinner authored in task 10).
  - Disabled state uses opacity 50%.
  - Author the static end-state of every state combination as a Figma variant; spring/ripple/shimmer motion is documented in design-system.md §8.2 and not reproduced here (wired in task 12 where Smart Animate supports it).
  - Blocked-by: uo74o2c (Author Figma colour variables (brand + Tailwind steps)), uo74o2d (Author Figma text styles for the typography scale)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3)

- [ ] 9. Author Input component with floating label and states <!-- id:uo74o2j -->
  - Build Input with default/focused/error/disabled states per design-system.md §3.2: base fill gray-800, text white, rounded-lg, border, 2px focus ring; state-specific borders/rings/label colours from the §3.2 table.
  - Floating-label behaviour: author two label-position variants — rest (vertically centred at text-base) and floated (-top-2.5 at text-xs font-medium with gray-800 background chip). Placeholder hidden when label is in its rest position.
  - Error state shows the error-message line below in red-400 text.
  - Bind fills/borders/text to colour variables from task 2 and text styles from task 3. Do not bake hex values.
  - Blocked-by: uo74o2c (Author Figma colour variables (brand + Tailwind steps)), uo74o2d (Author Figma text styles for the typography scale)
  - Stream: 1
  - Requirements: [5.2](requirements.md#5.2), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3)

- [ ] 10. Author EmptyState, ExpandableSection, LoadingSpinner, StorageError <!-- id:uo74o2k -->
  - EmptyState (§3.3): centred column, py-12 px-4, text-centre; title text-lg font-medium gray-200; description text-sm gray-400 max-w-sm; icon slot gray-500 above title; action slot below.
  - ExpandableSection (§3.4): rounded-lg, border gray-800, fill gray-900/50. Two variants — collapsed (chevron 0°) and expanded (chevron 180°, body panel with top border). Chevron uses an h-5 w-5 chevron-down icon (author inline or reuse a navigation-icon-style svg).
  - LoadingSpinner (§3.5): circular outline, rounded-full, border-2, border-current with top border transparent, colour brand-accent; three sizes sm 16, md 32, lg 48. Author the static end-state; rotation is documented in §8.5.
  - StorageError (§3.6): full-screen centred column, fill gray-900, p-6; warning icon h-12 w-12 red-400 in red-500/20 circular badge; title 'Storage Unavailable' text-xl font-bold white; body text gray-400 max-w-md; 'Common causes' list (gray-800 surface), monospace error panel (gray-800/50 surface, gray-500 text); primary 'Try Again' button (brand-accent fill, gray-900 text) and troubleshooting link.
  - Bind all fills/text/borders to the foundations variables and text styles from tasks 2 and 3.
  - Blocked-by: uo74o2c (Author Figma colour variables (brand + Tailwind steps)), uo74o2d (Author Figma text styles for the typography scale), uo74o2g (Author navigation icon components)
  - Stream: 1
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3)

- [ ] 11. Author LogoLoader pattern frame <!-- id:uo74o2l -->
  - Per design-system.md §3.7, author a single Figma frame showing the Logo at size lg (48px) in its animated end-state, representing the LogoLoader usage pattern.
  - Document the 200ms show-after delay and 600ms minimum display as frame metadata or an adjacent annotation; these timings are not reproducible as a Figma interaction.
  - This is a pattern reference frame, not a component variant set.
  - Blocked-by: uo74o2e (Author Logo component with variants and sizes)
  - Stream: 1
  - Requirements: [3.4](requirements.md#3.4)

## Animations

- [ ] 12. Wire Smart Animate interactions where the Figma API supports them <!-- id:uo74o2m -->
  - For each animation in design-system.md §8, author Smart Animate / prototype interactions between the existing component variants WHERE a faithful-enough approximation is possible: Button default ↔ hover ↔ pressed; Input rest ↔ floated label; ExpandableSection collapsed ↔ expanded (chevron rotation + body reveal).
  - WHERE the Figma Plugin API cannot reproduce the motion (Svelte Spring physics for Button press/ripple, custom keyframes for Logo loop, focus-shimmer underline, PageTransition fade/slide), leave the motion documented-only in design-system.md §8 and DO NOT author a misleading approximation.
  - Author PageTransition (§8.6) as two reference frames showing the entering and settled end-states (opacity 0 + translate(±30px) vs opacity 1 + translate(0)) for default fade and forward/back slide directions, rather than a prototype interaction.
  - Every animated component's default Figma variant SHALL match the reduced-motion end-state per design-system.md §8 (e.g. Logo fully-drawn, Button at scale 1, Input label at rest unless value present, ExpandableSection collapsed).
  - Blocked-by: uo74o2i (Author Button variant set with all states), uo74o2j (Author Input component with floating label and states), uo74o2k (Author EmptyState, ExpandableSection, LoadingSpinner, StorageError)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3)

## Verification

- [ ] 13. Verify primitives and interactions via screenshots <!-- id:uo74o2n -->
  - Use get_screenshot to capture each primitive (Button matrix, Input states, EmptyState, ExpandableSection collapsed + expanded, LoadingSpinner sizes, StorageError), the LogoLoader frame, and the PageTransition reference frames.
  - Compare against design-system.md §3 specs: fills, text, borders, paddings, min-heights, state-specific styling.
  - Confirm Smart Animate transitions trigger between expected variant pairs and that components without reproducible motion (Button ripple/shimmer, Logo loop, Input focus-shimmer, PageTransition slide) show the documented end-state only — no misleading prototype motion.
  - Confirm component fills/strokes/text bind to the foundations variables and styles rather than literal hex values (Requirement 2.3, 5.4).
  - Flag any clipped text, wrong variant, placeholder text, incorrect colour, or unbound literal value and re-author before marking complete.
  - Blocked-by: uo74o2i (Author Button variant set with all states), uo74o2j (Author Input component with floating label and states), uo74o2k (Author EmptyState, ExpandableSection, LoadingSpinner, StorageError), uo74o2l (Author LogoLoader pattern frame), uo74o2m (Wire Smart Animate interactions where the Figma API supports them)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
