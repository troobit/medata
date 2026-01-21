---
references:
    - docs/requirements.md
metadata:
    branch: dev-0
    status: active
---
# MeData Development Tasks

## UI Refinement

- [ ] 1. Consolidate camera entry: merge 'Add photo' button with 'AI Photo' smart entry into unified camera view
  - [ ] 1.1. Remove redundant 'Add photo' button from manual entry section
  - [ ] 1.2. Create unified CameraEntry component with processing mode selection

- [ ] 2. Add mode selector within camera view (AI analysis vs manual estimation vs label scan)

- [ ] 3. Restore alcohol logging UI with drink units and type selector (beer/wine/spirit/mixed)
  - [ ] 3.1. Add alcoholUnits and alcoholType fields to meal entry form
  - [ ] 3.2. Include drink type selector dropdown (Not specified, Beer/Cider, Wine, Spirits, Cocktails)

- [ ] 4. Add drink shortcuts grid (pint, wine, spirit, cocktail) with carb and alcohol unit presets

- [ ] 5. Update history view to display alcohol entries with decay indicator icon

## AI Model Validation

- [ ] 6. Create test data collection interface for food images with known carb content
  - [ ] 6.1. Admin mode to capture food images with verified macro data
  - [ ] 6.2. Export test dataset as JSON with image URLs and ground truth values
  - [ ] 6.3. Support importing nutrition research datasets (USDA, academic sources)

- [ ] 7. Build validation dataset from user corrections (original AI estimate vs corrected value)

- [ ] 8. Implement accuracy metrics dashboard (MAE, MAPE by food category)

- [ ] 9. Add prompt enhancement pipeline using correction history to improve estimates

- [ ] 10. Generate synthetic test images with reference objects for volume estimation validation

## Local Food Estimation

- [ ] 11. Implement reference card detection (credit card edge detection, perspective correction)

- [ ] 12. Build food region segmentation with user-assisted boundary selection

- [ ] 13. Create USDA FNDDS food density lookup with category search

- [ ] 14. Implement volume-to-macro conversion with confidence scoring

- [ ] 15. Store estimation calibration factors learned from user corrections

## Regression & Modeling

- [ ] 16. Model insulin decay function (biological half-life, compounding effects)

- [ ] 17. Model carbohydrate and alcohol absorption decay rates
  - [ ] 17.1. Research alcohol metabolism rates by drink type and body composition
  - [ ] 17.2. Implement alcohol-induced insulin sensitivity changes in BSL prediction

- [ ] 18. Implement time-of-day sensitivity adjustments for insulin response

- [ ] 19. Build BSL prediction model combining meal, insulin, and alcohol events

- [ ] 20. Create insulin dose recommendation engine with confidence intervals

## Future Enhancements

- [ ] 21. Implement Ollama/LLaVA self-hosted provider for offline AI estimation

- [ ] 22. Add direct CGM API integration (Freestyle Libre, Dexcom)

- [ ] 23. Build exercise event logging with wearable integration support

- [ ] 24. Implement authentication (FIDO/YubiKey support for multi-user)

- [ ] 25. Add meal preset management (save and recall common meals)

## Component System

- [ ] 26. Replace hover:scale-105 with contained animations to prevent button collision
  - [ ] 26.1. Use inner element transforms or box-shadow instead of scaling the button bounds
  - [ ] 26.2. Add gap/margin utilities to button containers to accommodate subtle motion

- [ ] 27. Add animation prop to Button (variant: 'none' | 'subtle' | 'full') for configurable effects
  - [ ] 27.1. Use Svelte 5.16+ class={{ }} object syntax for conditional animation classes

- [ ] 28. Replace custom CSS ripple/shimmer with Svelte Spring class and svelte/transition
  - [ ] 28.1. Use Svelte 5 Spring.of() for reactive scale feedback on press/release
  - [ ] 28.2. Replace @keyframes ripple-effect with svelte/transition scale function

- [ ] 29. Use svelte/easing functions instead of custom @keyframes animations

- [ ] 30. Integrate prefersReducedMotion from svelte/motion for accessibility compliance
