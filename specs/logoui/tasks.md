---
references:
    - specs/dev-2/requirements.md
    - static/icon.svg
    - src/lib/components/ui/LoadingSpinner.svelte
---
# Logo Component Implementation

## Phase 1: Core Logo Component

- [x] 1. Create Logo.svelte component with size props (sm, md, lg, splash)

- [x] 2. Implement inline SVG rendering from static/icon.svg structure

- [x] 3. Add size mapping: sm=16px, md=32px, lg=48px, splash=96px

- [x] 4. Export Logo from src/lib/components/ui/index.ts

- [x] 5. Add TypeScript props interface with size and class props

## Phase 2: Stroke-Draw Animation

- [x] 6. Split SVG path into three separate path elements for independent animation

- [x] 7. Ensure outer most edge of right vertical is perfectly in line with the out edge of the curve segment - such that the top of the line end is not seen.

- [x] 8. Calculate stroke-dasharray values for each path segment

- [x] 9. Create CSS @keyframes for draw animation (0% to 50%: draw on)

- [x] 10. Create CSS @keyframes for undraw animation (50% to 100%: draw off)

- [x] 11. Implement staggered timing: main path -> right vertical -> center dot (draw)

- [x] 12. Implement reverse stagger: center dot -> right vertical -> main path (undraw)

- [x] 13. Add animated prop to toggle animation on/off

- [x] 14. Add smooth easing and loop configuration

## Phase 3: Build-Time Variants

- [x] 15. Add PUBLIC_LOGO_VARIANT to .env.example with documentation

- [x] 16. Read PUBLIC_LOGO_VARIANT from env in Logo component

- [x] 17. Implement default variant color scheme (#63ff00 green)

- [x] 18. Implement contrast variant (black stroke, yellow center dot)

- [x] 19. Create SVG linearGradient definition for pride rainbow

- [x] 20. Implement pride variant with 6-color gradient stroke

- [x] 21. Add variant type validation and fallback to default

## Phase 4: Favicon Generation

- [x] 22. Create static/favicon-default.svg from icon.svg

- [x] 23. Create static/favicon-pride.svg with rainbow gradient

- [x] 24. Create static/favicon-contrast.svg with black/yellow scheme

- [x] 25. Update src/app.html to reference variant-aware favicon

- [x] 26. Add Apple touch icon variants (180x180)

- [x] 27. Implement build-time favicon selection based on PUBLIC_LOGO_VARIANT

## Phase 5: Site Integration

- [x] 28. Replace LoadingSpinner with Logo animated in +layout.svelte

- [x] 29. Add static Logo to AppShell header/navigation

- [x] 30. Update any other LoadingSpinner usages to use Logo where appropriate

- [x] 31. Test all three variants build correctly

- [x] 32. Verify animation performance on mobile devices

- [x] 33. Verify no visual regressions across app
