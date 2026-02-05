# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- IMealRepository interface for meal data persistence with CRUD operations
- CosmosMealRepository implementing Azure Cosmos DB storage with day-based partition keys
- IImageRepository interface for blob storage operations
- BlobImageRepository implementing Azure Blob Storage for meal images
- POST /api/images/upload endpoint for server-side image uploads
- POST /api/meals endpoint for creating new meals
- GET /api/meals/day/[date] endpoint for retrieving meals by day
- GET/PUT/DELETE /api/meals/[id] endpoints for meal retrieval, update, and deletion
- LogbookList component displaying meal history with expandable cards grouped by date
- MealDetail component for full meal detail view with image display and action buttons
- Meal API client service (meal-api.ts) for client-side API calls
- Integration tests for meal repository operations using in-memory implementation
- Decision log entries D-DES-016 (Image Upload Orchestration) and D-DES-017 (Cosmos DB Partition Strategy Validation)
- Home page now displays recent meals logbook with edit/delete functionality

### Changed
- Home page updated to load and display recent meals from API with loading and error states
- Added @azure/cosmos and @azure/storage-blob dependencies for Azure services
- Added @types/node for Node.js type definitions

- FoodItemCard component for inline editing of food items with large tap targets (44px minimum)
- MealEditor component for editing AI results before saving with auto-recalculating totals
- Timestamp adjustment in MealEditor defaulting to current time with backdating support
- Toast notification component for visual confirmation on save
- ToastContainer component and toast store for global notification management
- Full capture flow wiring: CameraCapture → AI Recognition → MealEditor → Save
- /capture route implementing the complete photo-to-save flow
- Integration tests for meal creation flow validating Zod schemas and timestamp handling

- Core TypeScript types for meals and food items (FoodItem, MacroData, RecognisedFoodItem, Meal, Preset)
- Zod validation schemas for food items with non-negative macro validation
- Property-based tests for macro calculation utility using fast-check
- sumMacros utility function for calculating total macros from food items array
- CameraCapture component with MediaDevices API support for rear-facing camera and gallery fallback
- ImagePreview component for displaying captured image with confirm/retake options
- IFoodRecognitionService interface for AI food recognition providers
- ClaudeFoodRecognitionService implementing Claude API integration with 10-second timeout
- POST /api/ai/recognise endpoint accepting base64 images and returning structured food recognition results
- FoodRecognitionResult component displaying itemised food list with macros and confidence scores
- AIErrorFallback component for handling AI recognition errors with retry and manual entry options
- AI prompt design documentation in specs/ai-prompt-design.md with Claude vision best practices
- Vitest configuration for unit testing with jsdom environment

### Changed
- Updated vite.config.ts to use vitest/config for test configuration

- Initial SvelteKit project scaffold with Svelte 5 and TypeScript strict mode
- Tailwind CSS 4.x configuration with brand colours (#63ff00 accent, #064e3b background, #0a0a0a primary)
- PWA manifest.json with app icons and theme colours
- app.html configured with favicons, manifest link, and theme-color meta tags
- AppShell layout component with header displaying MeData logo
- Home page with action buttons (Capture Meal, Manual Entry, From Preset) and empty logbook placeholder
- .env.example with required environment variable templates (ANTHROPIC_API_KEY, AZURE_COSMOS_CONNECTION_STRING, AZURE_BLOB_STORAGE_URL)
