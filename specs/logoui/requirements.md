# Logo Component & Branding Requirements

## Scope

This document details the requirements for a unified Logo component with animation and build-time variant support.

**In Scope:**
- Single `<Logo>` Svelte component with all variants
- Stroke-draw animation for loading states
- Build-time variant configuration (no frontend selection)
- Favicon generation per variant
- Integration across: loading screen, navigation/header, splash

**Out of Scope:**
- User-facing theme selection UI
- Runtime variant switching
- Accessibility changes beyond existing implementation

---

## Current State Summary

| Aspect | Current Implementation |
|--------|------------------------|
| Logo source | `static/icon.svg` - stroke-based SVG (128x128 viewBox, 512x512 render) |
| Loading indicator | `LoadingSpinner.svelte` - CSS-only rotating border |
| Sizing | sm (16px), md (32px), lg (48px) |
| Logo usage | Not currently used in app; icon.svg exists but isn't integrated |

**Key Files:**
- `static/icon.svg` - source logo (stroke-based, #63ff00 green)
- `src/lib/components/ui/LoadingSpinner.svelte` - current loading indicator
- `src/routes/+layout.svelte` - app shell with loading state
- `src/app.css` - global styles

---

## Logo Structure

The existing `static/icon.svg` structure:

```svg
<svg viewBox="0 0 128 128">
  <path stroke="#63ff00" stroke-width="24" stroke-linecap="round" stroke-linejoin="round"
    d="M 24,24
       C 130,24 130,104 24,104
       L 24,64
       M 104,64
       L 104,104
       M 64,64
       L 64,64" />
</svg>
```

**Path segments:**
1. Main curve and vertical: `M 24,24 C 130,24 130,104 24,104 L 24,64`
2. Right vertical: `M 104,64 L 104,104`
3. Center dot: `M 64,64 L 64,64` (renders as dot via stroke-linecap="round")

---

## Requirements

### 1. Logo Component

**Single unified component:** `src/lib/components/ui/Logo.svelte`

**Props:**
- `size`: 'sm' | 'md' | 'lg' | 'splash' (follows existing pattern, adds splash for larger contexts)
- `animated`: boolean (default: false) - enables stroke-draw animation
- `class`: string (optional) - additional CSS classes

**Size mapping:**
- sm: 16px (inline icons)
- md: 32px (nav/header)
- lg: 48px (loading states)
- splash: 96px+ (full-screen loading)

**Behavior:**
- SVG is always source of truth for shape
- Variant colors applied via CSS custom properties or inline styles
- Component reads variant from build-time config

---

### 2. Animation

**Type:** Stroke-draw effect using `stroke-dasharray` and `stroke-dashoffset`

**Behavior:**
- Loops continuously when `animated=true`
- Draw sequence: main path draws on → right vertical → center dot (last)
- Undraw sequence: center dot disappears first → right vertical → main path
- Smooth easing between draw and undraw phases

**Implementation approach:**
- CSS animations preferred (no JS runtime)
- Use `@keyframes` for draw/undraw cycle
- Staggered animation delays for path segments

---

### 3. Build-Time Variants

**Configuration:** Environment variable in `.env` file

```
PUBLIC_LOGO_VARIANT=default
```

**Supported variants:**

| Variant | Center Dot | Main Stroke | Notes |
|---------|------------|-------------|-------|
| `default` | #63ff00 | #63ff00 | Current green, single color |
| `pride` | gradient | linear gradient (rainbow) | Full rainbow gradient across stroke |
| `contrast` | #ffcc00 (yellow) | #000000 (black) | High contrast variant |

**Pride gradient colors:** Standard 6-color pride flag
- Red (#E40303)
- Orange (#FF8C00)
- Yellow (#FFED00)
- Green (#008026)
- Blue (#24408E)
- Violet (#732982)

---

### 4. Favicon

**Requirement:** Favicon must swap based on build variant

**Implementation:**
- Generate favicon variants at build time or store pre-generated versions
- Update `src/app.html` or use dynamic link injection based on variant
- Support standard favicon sizes (16x16, 32x32, 180x180 for Apple touch)

---

### 5. Integration Points

**Replace LoadingSpinner with Logo:**
- `src/routes/+layout.svelte` - app loading state (use `<Logo animated size="splash" />`)
- Any component currently using `<LoadingSpinner />` should optionally use `<Logo animated />`

**Add Logo to navigation:**
- `src/lib/components/layout/AppShell.svelte` or appropriate header location
- Static (non-animated) display: `<Logo size="md" />`

---

## Phases

### Phase 1: Core Logo Component

**Scope:** Create the base Logo component with size variants and default colors.

**Deliverables:**
- [ ] `src/lib/components/ui/Logo.svelte` - base component with size props
- [ ] Export from `src/lib/components/ui/index.ts`
- [ ] Default variant only (current green)

**Files to Add/Change:**
- Add: `src/lib/components/ui/Logo.svelte`
- Change: `src/lib/components/ui/index.ts`

---

### Phase 2: Stroke-Draw Animation

**Scope:** Implement the continuous draw/undraw animation.

**Deliverables:**
- [ ] CSS keyframe animations for stroke-draw effect
- [ ] Staggered timing: main path → right vertical → center dot
- [ ] Reverse sequence for undraw phase
- [ ] `animated` prop to toggle animation

**Files to Change:**
- `src/lib/components/ui/Logo.svelte`

---

### Phase 3: Build-Time Variants

**Scope:** Add variant support via environment configuration.

**Deliverables:**
- [ ] Read `PUBLIC_LOGO_VARIANT` from environment
- [ ] Implement color schemes for: default, pride, contrast
- [ ] Pride rainbow gradient implementation
- [ ] Document variant configuration in README or comments

**Files to Add/Change:**
- Change: `src/lib/components/ui/Logo.svelte`
- Change: `.env.example` (add PUBLIC_LOGO_VARIANT)

---

### Phase 4: Favicon Generation

**Scope:** Variant-aware favicon support.

**Deliverables:**
- [ ] Pre-generated or build-time generated favicons per variant
- [ ] Favicon switching based on PUBLIC_LOGO_VARIANT
- [ ] Standard sizes: 16x16, 32x32, 180x180 (Apple touch icon)

**Files to Add/Change:**
- Add: `static/favicon-default.svg` (or .ico/.png)
- Add: `static/favicon-pride.svg`
- Add: `static/favicon-contrast.svg`
- Change: `src/app.html` or add favicon logic to layout

---

### Phase 5: Site Integration

**Scope:** Replace existing loading states and add logo to navigation.

**Deliverables:**
- [ ] Replace `<LoadingSpinner />` with `<Logo animated />` in layout
- [ ] Add static logo to app header/navigation
- [ ] Verify no visual regressions

**Files to Change:**
- `src/routes/+layout.svelte`
- `src/lib/components/layout/AppShell.svelte`

---

## Risks and Notes

### Risks

1. **SVG gradient animation performance** - Linear gradients on animated strokes may have performance implications on low-end devices. Mitigation: test on target devices, consider fallback to solid color animation.

2. **Favicon caching** - Browsers aggressively cache favicons. Variant changes may not appear immediately. Mitigation: use cache-busting query params or versioned filenames.

3. **Path length calculation** - Stroke-draw animation requires accurate path length for `stroke-dasharray`. The multi-segment path may need segment-by-segment calculation.

### Notes

- The center dot (`M 64,64 L 64,64`) renders as a circle due to `stroke-linecap="round"` with `stroke-width="24"`, creating a 24px diameter dot.
- Keep LoadingSpinner.svelte available as fallback; don't delete until Logo is fully validated.
- Animation should use CSS only (no JS) to minimize bundle impact and ensure smooth performance.
- All variant logic is build-time; no runtime variant switching required.
