---
references:
    - specs/requirements.md
    - specs/design.md
    - specs/decision_log.md
---
# MeData MVP Implementation Tasks

## Phase 1: Project Scaffold & Branding

- [x] 1. Initialize SvelteKit project with Svelte 5 and TypeScript strict mode
  - Research SvelteKit best practices before setup
  - Configure tsconfig.json with strict mode per constitution §6.4
  - Verify npm run dev starts successfully

- [x] 2. Configure Tailwind CSS 4.x with brand colours
  - Brand accent: #63ff00 (neon green)
  - Brand background: #064e3b (dark teal)
  - Primary background: #0a0a0a (gray-950)
  - Per constitution §10

- [x] 3. Create PWA manifest.json with existing static assets
  - Req NF.5: PWA installable
  - Use static/icon.svg as primary icon
  - Use static/favicon.ico as fallback
  - Set theme_color to #63ff00
  - Set background_color to #0a0a0a

- [x] 4. Configure app.html with favicons and manifest link
  - Link favicon-default.svg as primary icon
  - Link favicon.ico as alternate
  - Add manifest link
  - Add theme-color meta tag
  - Add apple-mobile-web-app-capable meta

- [x] 5. Create AppShell layout component with logo
  - Req 9.1, 9.2, 9.4: Mobile-first responsive layout
  - Integrate static/icon.svg in header
  - 44px minimum tap targets

- [x] 6. Create home page with action buttons
  - Req 9.1, 9.2: Mobile-first UI
  - Capture Meal button
  - Manual Entry button
  - From Preset button
  - Empty logbook placeholder
  - Per design §7.5 first-run experience

- [x] 7. Create .env.example with required environment variables
  - Req 11.1: Load API keys from env vars
  - ANTHROPIC_API_KEY - Claude API key for food recognition
  - AZURE_COSMOS_CONNECTION_STRING - Cosmos DB connection string
  - AZURE_BLOB_STORAGE_URL - Blob storage container URL with SAS token
  - Document all required vars with descriptions
  - Note: .env.local should be updated to use these standardised names

## Phase 2: Photo Capture & AI Recognition

- [ ] 8. Create core TypeScript types for meals and food items
  - FoodItem interface (name, carbs, protein, fat)
  - MacroData interface
  - MealDataSource type
  - RecognisedFoodItem interface (with quantity/unit for AI response)
  - Per design §4.1

- [ ] 9. Create Zod validation schemas for food items
  - Req 3.4: Validate non-negative numbers
  - Req 10.3, 10.5: Raw grams, no artificial ranges
  - FoodItemSchema with nonnegative() validation

- [ ] 10. Write property-based tests for macro calculation utility
  - Use fast-check for PBT
  - Property: Sum is always non-negative
  - Property: Empty array returns zeros
  - Property: Single item returns same values
  - Per design §6.3
  - Test-first: write before implementation

- [ ] 11. Implement sumMacros utility function
  - Calculate totals from FoodItem array
  - Used before saving meals (D-DES-012)
  - Must pass property-based tests from task 10

- [ ] 12. Create CameraCapture component
  - Req 1.1: Use rear-facing camera via MediaDevices API
  - Req 1.2: Accept JPEG and PNG only
  - Req 1.5: Mobile-first
  - Req 1.6: Gallery upload fallback via file input

- [ ] 13. Create ImagePreview component
  - Req 1.3: Display preview before AI analysis
  - Req 1.4: Allow retake if unsatisfactory
  - Confirm and Cancel buttons

- [ ] 14. Create IFoodRecognitionService interface
  - Per design §3.3
  - recognise(image, labelContext?) method
  - isConfigured() method
  - getProviderName() method

- [ ] 15. [RESEARCH] AI prompt design for food recognition
  - RESEARCH TASK - no code changes
  - Per design §1.5 research tasks
  - Test prompts with various food photos
  - Document final prompt template in specs/
  - Ensure structured JSON output (D-DES-001)

- [ ] 16. Implement Claude food recognition service
  - Req 2.1, 2.8: Send images to Claude API
  - Req 2.6: 10-second timeout (D-DES-013)
  - Use structured JSON mode (D-DES-001)
  - Return RecognisedFoodItem array
  - Depends on research task 15

- [ ] 17. Create POST /api/ai/recognise endpoint
  - Per design §4.4
  - Accept imageBase64 and mimeType
  - Return items, totalMacros, confidence, provider, processingTimeMs
  - Handle timeout and errors per design §5.1

- [ ] 18. Create FoodRecognitionResult component
  - Req 2.2: Display itemised list with macros
  - Req 2.3: Show confidence score for each item
  - Req 2.4: Show all results regardless of confidence
  - Req 2.5: Calculate and display aggregate totals

- [ ] 19. Implement AI error handling with manual entry fallback
  - Req 2.7: On failure, show error and offer manual entry
  - Req 2.10: On zero items, offer retry or manual entry
  - D-DES-013: Show Try Again and Enter Manually buttons on timeout

## Phase 3: Edit, Review & Save Flow

- [ ] 20. Create Meal type and CreateMealInput schema
  - Per design §4.1
  - Include totalCarbs, totalProtein, totalFat (D-DES-012)
  - Zod schema for validation
  - Req 4.1: timestamp, items, totals, source, imageUrl

- [ ] 21. Create FoodItemCard component
  - Req 3.7, 9.2: Large tap targets (44px minimum)
  - Req 5.2: Inline editing of name, carbs, protein, fat
  - Req 5.3: Remove item button
  - Optional confidence badge display

- [ ] 22. Create MealEditor component
  - Req 3.6, 5.1: Editable AI results before saving
  - Req 3.2, 5.4: Add new food items
  - Req 3.3, 5.5: Auto-recalculate totals on change
  - Req 5.6: Preserve original AI confidence scores

- [ ] 23. Add timestamp adjustment to MealEditor
  - Req 4.4: Default to current time
  - Req 4.5: Allow backdating meals
  - Req 4.7: Store as UTC Unix milliseconds

- [ ] 24. Create Toast notification component
  - Req 4.6: Visual confirmation on save
  - Req 9.7: Direct messages without apologies
  - Show Meal saved on successful save

- [ ] 25. Wire capture flow: CameraCapture → AI → MealEditor → Save
  - Req 9.3: Complete in 3 or fewer actions
  - Photo → Review → Save flow
  - Convert RecognisedFoodItem to FoodItem (discard quantity/unit per D-DES-014)
  - Integrates tasks 12, 13, 17, 18, 22

- [ ] 26. Write integration tests for meal creation flow
  - Test Zod validation rejects negative macros
  - Test totals are calculated correctly
  - Test timestamp is stored as UTC Unix ms
  - Depends on tasks 9, 11, 20

## Phase 4: Meal Storage & History

- [ ] 27. [RESEARCH] Cosmos DB partition strategy for day-based queries
  - RESEARCH TASK - no code changes
  - Per design §1.5 research tasks
  - Validate day-based partition key (YYYY-MM-DD)
  - Test date range query performance
  - Document findings in specs/ and update design if needed
  - Azure credentials configured - ready to test

- [ ] 28. [RESEARCH] Image upload orchestration best practices
  - RESEARCH TASK - no code changes
  - Per design §1.5 research tasks
  - Best practice for capture → upload → AI → save flow
  - Per D-DES-010: Server-side upload using @azure/storage-blob
  - Document sequence in specs/ and update design if needed
  - Azure credentials configured - ready to test

- [ ] 29. Create IMealRepository interface
  - Per design §3.3
  - create, getById, getByDay, getByDateRange, update, delete methods
  - Req 4.8: Never delete without explicit user action

- [ ] 30. Implement Cosmos DB meal repository
  - Per design §4.2
  - Use YYYY-MM-DD partition key (D-DES-007)
  - Req 10.1, 10.2: Set createdAt and updatedAt timestamps
  - Use @azure/cosmos SDK
  - Uses AZURE_COSMOS_CONNECTION_STRING from .env.local

- [ ] 31. Create IImageRepository interface
  - Per design §3.3
  - upload(image, folder, filename) returns URL
  - delete(url) method

- [ ] 32. Implement Azure Blob Storage image repository
  - Req 4.3, 11.2: Secure server-side upload
  - Per design §4.3: images/meals/ and images/labels/ folders
  - D-DES-002: 30-day TTL via lifecycle policy (configure in Azure portal)
  - Max 10MB image size
  - Uses AZURE_BLOB_STORAGE_URL from .env.local

- [ ] 33. Create POST /api/images/upload endpoint
  - Per design §3.4
  - Accept multipart/form-data
  - Validate JPEG/PNG and size limit
  - Return imageUrl
  - Req 11.5: Credentials server-side only

- [ ] 34. Create meal API endpoints
  - Per design §4.4
  - POST /api/meals - create meal
  - GET /api/meals/day/[date] - get by day
  - GET /api/meals/[id] - get by ID
  - PUT /api/meals/[id] - update
  - DELETE /api/meals/[id] - delete

- [ ] 35. Create LogbookList component
  - Req 8.1: Chronological list, newest first
  - Req 8.2: Show timestamp, total carbs, item count
  - Per design §3.2: Expandable cards

- [ ] 36. Create MealDetail component
  - Req 8.3: Expand to view full details
  - Req 8.6: Display associated photo if available
  - D-DES-004: Show placeholder on image 404
  - Edit and Delete action buttons

- [ ] 37. Implement edit saved meal functionality
  - Req 8.4: Edit saved meals after storage
  - Open MealEditor with existing data
  - Update via PUT /api/meals/[id]
  - Update updatedAt timestamp

- [ ] 38. Implement delete meal functionality
  - Req 8.5: Delete from logbook
  - Confirmation before delete
  - Delete via DELETE /api/meals/[id]

- [ ] 39. Wire logbook into home page
  - Show recent meals on home page
  - Navigate to full logbook view
  - Per design §7.5: Logbook: No meals yet when empty

- [ ] 40. Write integration tests for meal CRUD operations
  - Test create returns 201 with all fields
  - Test getByDay returns correct meals
  - Test update modifies updatedAt
  - Test delete removes meal
  - Depends on tasks 30, 34

## Phase 5: Manual Entry Mode

- [ ] 41. Create ManualEntryForm component
  - Req 3.1: Minimal form with name, carbs, protein, fat
  - Req 3.5: Works without requiring a photo
  - Req 3.7: Large tap targets for quick adjustment
  - Optional photo attachment

- [ ] 42. Add multiple items support to ManualEntryForm
  - Req 3.2: Add multiple food items to single meal
  - Req 3.3: Auto-calculate aggregate totals
  - Add Item button

- [ ] 43. Wire ManualEntryForm to MealEditor and save flow
  - Req 4.2: Record source as manual
  - Navigate ManualEntryForm → MealEditor → Save
  - Save with source: manual

- [ ] 44. Connect Manual Entry button on home page
  - Navigate to ManualEntryForm
  - Return to home after save
  - Toast confirmation on save

## Phase 6: Meal Presets

- [ ] 45. Create Preset type and Zod schemas
  - Per design §4.1
  - Req 6.1: Allow emoji-only names
  - Req 6.2: name, category (meal/snack), items, totals
  - PresetCategory type: meal | snack

- [ ] 46. Create IPresetRepository interface
  - Per design §3.3
  - create, getById, getAll, getByCategory, update, delete methods

- [ ] 47. Implement Cosmos DB preset repository
  - Per design §4.2
  - Use /category partition key
  - presets container in medata database
  - Uses AZURE_COSMOS_CONNECTION_STRING from .env.local

- [ ] 48. Create preset API endpoints
  - POST /api/presets - create
  - GET /api/presets - list all
  - GET /api/presets/[id] - get by ID
  - PUT /api/presets/[id] - update
  - DELETE /api/presets/[id] - delete

- [ ] 49. Add Save as Preset button to MealEditor
  - Req 6.1: Save any meal as named preset
  - Prompt for name and category
  - Save via POST /api/presets

- [ ] 50. Create PresetCard component
  - Display preset name and total macros
  - Tap to apply
  - Edit/delete actions

- [ ] 51. Create PresetList component
  - Req 6.3: List all presets
  - Group by category (meal/snack)
  - Tap preset to apply

- [ ] 52. Implement apply preset functionality
  - Req 6.3: Create new meal in single action
  - Req 6.8: Allow modification before saving
  - Navigate PresetList → MealEditor with preset data
  - Save with source: preset

- [ ] 53. Implement edit/delete preset functionality
  - Req 6.6: Edit preset details after creation
  - Req 6.7: Delete presets
  - Confirmation before delete

- [ ] 54. Connect From Preset button on home page
  - Navigate to PresetList
  - Show No presets yet when empty
  - Return to home after applying preset

- [ ] 55. Write integration tests for preset CRUD operations
  - Test create with emoji name
  - Test getByCategory returns correct presets
  - Test update and delete
  - Depends on tasks 47, 48

## Phase 7: Label Scanning (Unified Flow)

- [ ] 56. Add Add Label button to CameraCapture
  - Req 7.1: Accept photos of nutrition labels
  - Optional - user photographs food first, then can add label
  - Per D-DES-006: Unified flow, not separate workflow

- [ ] 57. Create LabelContext interface and capture flow
  - Per design §3.3: LabelContext with labelImage
  - Capture food image first, then optional label image
  - Pass both to AI endpoint

- [ ] 58. Update AI prompt for label-enhanced recognition
  - Req 7.2: Extract serving size, carbs, protein, fat from Australian labels
  - Req 7.4: Estimate servings from food photo
  - Req 7.5: Calculate macros from servings × per-serving values
  - Per design §3.3 prompt template

- [ ] 59. Update /api/ai/recognise to accept optional label image
  - Accept labelBase64 and labelMimeType optional fields
  - Pass to AI service as LabelContext
  - Same response format with improved accuracy

- [ ] 60. Implement label parsing fallback to manual entry
  - Req 7.6: On parse failure, offer manual entry
  - Same error handling as standard recognition
  - User can still save with manual macros

- [ ] 61. Test label scanning with Australian nutrition labels
  - Curate test photos of Australian nutrition labels
  - Test per-serving and per-100g extraction
  - Verify portion estimation from food photo
  - Manual testing per design §6.2
