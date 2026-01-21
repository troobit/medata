---
references:
    - specs/logoui/requirements.md
    - static/icon.svg
    - src/lib/components/ui/LoadingSpinner.svelte
---
# Logo Component Implementation

## Phase 0: Recover work in progress - add to current commit (rebase was required)

- [x] 1. Use branch dev-2 and commit fc1c25e to look at changes to files and logo process.

- [x] 2. Merge changes being sure to ensure no conflicts with current branch (logoui), which is more appropriately named

- [x] 3. Ensure logo is updated per needs with requirements still met. You are to assume none of the below jobs are complete until you can prove they are.

- [x] 4. Create Logo.svelte component with size props (sm, md, lg, splash)

- [x] 5. Implement inline SVG rendering from static/icon.svg structure

- [x] 6. Add size mapping: sm=16px, md=32px, lg=48px, splash=96px

- [x] 7. Export Logo from src/lib/components/ui/index.ts

## Phase 1: Core Logo Component

- [x] 8. Add TypeScript props interface with size and class props

## Phase 2: Stroke-Draw Animation

- [x] 9. Split SVG path into three separate path elements for independent animation

- [x] 10. Ensure outer most edge of right vertical is perfectly in line with the out edge of the curve segment - such that the top of the line end is not seen.

- [x] 11. Calculate stroke-dasharray values for each path segment

- [x] 12. Create CSS @keyframes for draw animation (0% to 50%: draw on)

- [x] 13. Create CSS @keyframes for undraw animation (50% to 100%: draw off)

- [x] 14. Implement staggered timing: main path -> right vertical -> center dot (draw)

- [x] 15. Implement reverse stagger: center dot -> right vertical -> main path (undraw)

- [x] 16. Add animated prop to toggle animation on/off

- [x] 17. Add smooth easing and loop configuration

## Phase 3: Build-Time Variants

- [x] 18. Add PUBLIC_LOGO_VARIANT to .env.example with documentation

- [x] 19. Read PUBLIC_LOGO_VARIANT from env in Logo component

- [x] 20. Implement default variant color scheme (#63ff00 green)

- [x] 21. Implement contrast variant (black stroke, yellow center dot)

- [x] 22. Create SVG linearGradient definition for pride rainbow

- [x] 23. Implement pride variant with 6-color gradient stroke

- [x] 24. Add variant type validation and fallback to default

## Phase 4: Favicon Generation

- [x] 25. Create static/favicon-default.svg from icon.svg

- [x] 26. Create static/favicon-pride.svg with rainbow gradient

- [x] 27. Create static/favicon-contrast.svg with black/yellow scheme

- [x] 28. Update src/app.html to reference variant-aware favicon

- [x] 29. Add Apple touch icon variants (180x180)

- [x] 30. Implement build-time favicon selection based on PUBLIC_LOGO_VARIANT

## Phase 5: Site Integration

- [ ] 31. Replace LoadingSpinner with Logo animated in +layout.svelte

- [ ] 32. Add static Logo to AppShell header/navigation

- [ ] 33. Update any other LoadingSpinner usages to use Logo where appropriate

- [ ] 34. Test all three variants build correctly

- [ ] 35. Verify animation performance on mobile devices

- [ ] 36. Verify no visual regressions across app
