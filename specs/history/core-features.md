# Core MeData Features

**Branch:** `dev-0`

## Overview

Established the core functionality of the MeData diabetes management application, including UI refinements, AI-powered food estimation, local estimation pipelines, regression modelling, and foundational authentication support.

## Implementation Summary

Built a comprehensive diabetes tracking application with:
- Unified camera-based food entry with AI analysis
- Alcohol logging with drink type presets
- AI model validation and accuracy metrics
- Local food estimation using reference objects
- Regression models for insulin, carbohydrates, and alcohol
- Exercise and CGM integration support
- Svelte 5 component system with modern animations

## Features Implemented

### UI Refinement
- Consolidated camera entry merging 'Add photo' with 'AI Photo' smart entry
- Created unified CameraEntry component with processing mode selection
- Added mode selector within camera view (AI analysis / manual estimation / label scan)
- Restored alcohol logging UI with drink units and type selector
- Added drink shortcuts grid with carb and alcohol unit presets
- Updated history view with alcohol decay indicator icons

### AI Model Validation
- Test data collection interface for food images with known carb content
- Admin mode for capturing food images with verified macro data
- Export test dataset as JSON with image URLs and ground truth values
- Support for importing nutrition research datasets (USDA, academic sources)
- Validation dataset from user corrections (original AI estimate vs corrected value)
- Accuracy metrics dashboard (MAE, MAPE by food category)
- Prompt enhancement pipeline using correction history
- Synthetic test image generation with reference objects

### Local Food Estimation
- Reference card detection with credit card edge detection and perspective correction
- Food region segmentation with user-assisted boundary selection
- USDA FNDDS food density lookup with category search
- Volume-to-macro conversion with confidence scoring
- Estimation calibration factors learned from user corrections

### Regression & Modelling
- Insulin decay function modelling (biological half-life, compounding effects)
- Carbohydrate and alcohol absorption decay rates
- Alcohol metabolism rates by drink type and body composition
- Alcohol-induced insulin sensitivity changes in BSL prediction
- Time-of-day sensitivity adjustments for insulin response
- BSL prediction model combining meal, insulin, and alcohol events
- Insulin dose recommendation engine with confidence intervals

### Future Enhancements (Foundations)
- Ollama/LLaVA self-hosted provider for offline AI estimation
- Direct CGM API integration (Freestyle Libre, Dexcom)
- Exercise event logging with wearable integration support
- FIDO/YubiKey authentication support for multi-user
- Meal preset management (save and recall common meals)

### Component System
- Replaced hover:scale-105 with contained animations
- Added animation prop to Button (variant: 'none' | 'subtle' | 'full')
- Replaced custom CSS ripple/shimmer with Svelte Spring and svelte/transition
- Used Svelte 5 Spring.of() for reactive scale feedback
- Integrated prefersReducedMotion for accessibility compliance

## Files Changed

### Components Added
- `src/lib/components/ai/CameraCapture.svelte`
- `src/lib/components/ai/FoodItemEditor.svelte`
- `src/lib/components/ai/FoodRecognitionResult.svelte`
- `src/lib/components/ai/NutritionLabelScanner.svelte`
- `src/lib/components/ai/ReferencePlacement.svelte`
- `src/lib/components/alcohol/AlcoholEntry.svelte`
- `src/lib/components/alcohol/DrinkShortcuts.svelte`
- `src/lib/components/exercise/ExerciseEntry.svelte`
- `src/lib/components/import/CSVUpload.svelte`
- `src/lib/components/import/ImportPreview.svelte`
- `src/lib/components/import/ImportProgress.svelte`
- `src/lib/components/import/DuplicateResolver.svelte`
- `src/lib/components/modeling/BSLPrediction.svelte`
- `src/lib/components/modeling/InsulinRecommendation.svelte`
- `src/lib/components/presets/MealPresetManager.svelte`
- `src/lib/components/ui/Button.svelte`
- `src/lib/components/Logo.svelte`

### Services Added
- `src/lib/services/ai/` - Multi-provider AI food estimation (Azure, Gemini, Claude, OpenAI, Bedrock, Local)
- `src/lib/services/cgm/` - CGM integration services (Dexcom, Libre)
- `src/lib/services/decay/` - Decay function calculations
- `src/lib/services/estimation/` - Local food estimation pipeline
- `src/lib/services/import/CSVParser.ts` - CSV import handling
- `src/lib/services/modeling/` - Regression and prediction models
- `src/lib/services/validation/` - AI model validation

### Types Added
- `src/lib/types/ai.ts`
- `src/lib/types/cgm.ts`
- `src/lib/types/exercise.ts`
- `src/lib/types/import.ts`
- `src/lib/types/local-estimation.ts`
- `src/lib/types/modeling.ts`
- `src/lib/types/validation.ts`
- `src/lib/types/vision.ts`

### Routes Added
- `src/routes/import/` - Data import pages
- `src/routes/import/bsl/` - BSL time-series import
- `src/routes/import/cgm/` - CGM data import
- `src/routes/log/bsl/` - BSL logging
- `src/routes/log/exercise/` - Exercise logging
- `src/routes/log/meal/camera/` - Unified camera entry
- `src/routes/log/meal/estimate/` - Local estimation
- `src/routes/log/meal/label/` - Nutrition label scanning
- `src/routes/log/meal/photo/` - Photo-based entry
- `src/routes/validation/` - AI validation dashboard
- `src/routes/validation/capture/` - Validation data capture

### Utilities Added
- `src/lib/utils/csvHelpers.ts`
- `src/lib/utils/curveExtraction.ts`
- `src/lib/utils/dateNormalization.ts`
- `src/lib/utils/imageProcessing.ts`
- `src/lib/utils/motion.svelte.ts`

## Documentation Updates

- `docs/requirements.md` - Core system requirements
- `src/lib/components/ai/README.md` - AI component documentation
- `src/lib/services/ai/README.md` - AI service documentation

## Design Decisions

See `docs/design.md` for architectural decisions including:
- Event-log data paradigm
- Multi-provider AI service architecture
- Local estimation pipeline design
- Svelte 5 component patterns
