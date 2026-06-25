# MVP Refinement — Requirements

**Version:** 1.0
**Date:** 2026-03-12
**Status:** Draft
**Branch:** dev-sdd

## Introduction

The MeData MVP (Phases 1–7) is code-complete on the `dev-sdd` branch but has never been validated end-to-end with real data. This spec covers the work required to make every feature actually function — camera capture on mobile, AI food recognition with a real API key, and the complete capture → recognise → edit → save → view flow.

Key drivers:
- **Camera capture** only needs to work on mobile (phone). Desktop users use gallery upload.
- **AI recognition** needs a working API key from console.anthropic.com, plus a mock mode for development iteration.
- **Local dev** is the target environment — no cloud deployment required yet.
- **Azure backend** (Cosmos DB + Blob Storage) is already provisioned.
- **No existing data** — clean slate, no migration concerns.

---

## Requirements

### 1. HTTPS Dev Server for Mobile Camera Access

**User Story:** As a developer, I want to access the dev server from my phone over HTTPS, so that the browser permits camera access via getUserMedia.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN the dev server starts, THEN it SHALL serve over HTTPS using a self-signed certificate (e.g. `@vitejs/plugin-basic-ssl` or equivalent)
2. <a name="1.2"></a>The dev server SHALL be accessible from other devices on the same local network via the host machine's LAN IP (e.g. `https://192.168.x.x:5173`)
3. <a name="1.3"></a>The setup SHALL NOT require any external tunnelling service (ngrok, Cloudflare Tunnel, etc.)
4. <a name="1.4"></a>The existing HTTP localhost development workflow SHALL continue to work for non-camera features

### 2. Mobile Camera Capture Validation

**User Story:** As a user on my phone, I want to take a photo of my food using the rear camera, so that I can log a meal via AI recognition.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN the user navigates to the capture page on a mobile browser over HTTPS, THEN the app SHALL request camera permission and display a live rear-camera viewfinder
2. <a name="2.2"></a>WHEN the user taps the capture button, THEN the app SHALL take a still photo and display a preview with retake and confirm options
3. <a name="2.3"></a>IF camera permission is denied or the device has no camera, THEN the app SHALL show the gallery upload fallback without errors
4. <a name="2.4"></a>The camera component SHALL release the media stream when the user navigates away from the capture page
5. <a name="2.5"></a>On desktop browsers, the capture page SHALL show only the gallery upload option (no camera viewfinder)

### 3. Desktop Gallery Upload

**User Story:** As a developer testing on my MacBook, I want to upload a photo from my gallery, so that I can test the AI recognition flow without a phone camera.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN the user is on a desktop browser, THEN the capture page SHALL display a file picker for image upload (JPEG, PNG)
2. <a name="3.2"></a>WHEN the user selects an image file, THEN the app SHALL display the same preview with confirm/re-select options as the camera flow
3. <a name="3.3"></a>The gallery upload flow SHALL feed into the same AI recognition pipeline as camera-captured photos

### 4. Anthropic API Key Configuration

**User Story:** As a developer, I want clear instructions for obtaining and configuring an Anthropic API key, so that I can enable AI food recognition.

**Acceptance Criteria:**

1. <a name="4.1"></a>The project SHALL include a documented step-by-step guide in the developer docs for creating an account at console.anthropic.com and generating an API key
2. <a name="4.2"></a>The `.env.example` file SHALL list `ANTHROPIC_API_KEY` with a comment explaining it is required for AI recognition and where to obtain it
3. <a name="4.3"></a>WHEN the API key is missing or invalid, THEN the `/api/ai/recognise` endpoint SHALL return a 503 status with a clear error message indicating the key is not configured
4. <a name="4.4"></a>WHEN the API key is missing, THEN the capture UI SHALL detect this and offer direct manual entry instead of attempting AI recognition

### 5. Mock AI Recognition Mode

**User Story:** As a developer, I want a mock AI mode that returns realistic fake food data, so that I can test the full capture-to-save flow without consuming API credits.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN the environment variable `AI_MOCK_MODE` is set to `true`, THEN the `/api/ai/recognise` endpoint SHALL return mock food recognition data instead of calling the Claude API
2. <a name="5.2"></a>The mock response SHALL match the exact same schema as a real Claude API response (items array with name, carbs, protein, fat, confidence; overallConfidence; notes)
3. <a name="5.3"></a>The mock data SHALL contain 2–4 realistic food items with plausible macro values (e.g. "Grilled chicken breast" with 0g carbs, 31g protein, 3.6g fat)
4. <a name="5.4"></a>The mock response SHALL include a 500ms–1500ms artificial delay to simulate real API latency
5. <a name="5.5"></a>WHEN mock mode is active, THEN the UI SHALL display a visible indicator (e.g. a banner or badge) so the developer knows AI responses are mocked
6. <a name="5.6"></a>The mock service SHALL implement the same `FoodRecognitionService` interface as the real Claude service, selectable via environment configuration

### 6. End-to-End Capture Flow Validation

**User Story:** As a user, I want to photograph my food, review the AI-estimated macros, edit if needed, and save the meal, so that I have an accurate record of what I ate.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN the user captures or uploads a photo and confirms it, THEN the app SHALL send the image to the AI recognition endpoint and display a loading state
2. <a name="6.2"></a>WHEN AI recognition completes, THEN the app SHALL display the recognised food items with their macro estimates in the meal editor
3. <a name="6.3"></a>The user SHALL be able to edit item names, macro values, add items, and remove items before saving
4. <a name="6.4"></a>WHEN the user saves the meal, THEN the image SHALL be uploaded to Azure Blob Storage and the meal record SHALL be persisted to Cosmos DB
5. <a name="6.5"></a>WHEN the meal is saved, THEN the user SHALL be redirected to the home page where the new meal appears in the logbook
6. <a name="6.6"></a>IF AI recognition fails (timeout, error, no items), THEN the app SHALL offer manual entry as a fallback without losing the captured photo

### 7. Manual Entry Flow Validation

**User Story:** As a user, I want to manually enter food items and their macros, so that I can log meals that aren't suitable for photo recognition.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN the user navigates to manual entry, THEN the app SHALL display a form with fields for item name, carbs (g), protein (g), and fat (g)
2. <a name="7.2"></a>The user SHALL be able to add multiple food items to a single meal before saving
3. <a name="7.3"></a>WHEN the user saves a manual meal, THEN it SHALL be persisted to Cosmos DB with `source: 'manual'` and appear in the logbook

### 8. Meal History and Logbook Validation

**User Story:** As a user, I want to see my logged meals in a daily logbook, so that I can review what I've eaten and track my macros.

**Acceptance Criteria:**

1. <a name="8.1"></a>WHEN the home page loads, THEN the app SHALL fetch and display today's meals from Cosmos DB, ordered by timestamp (most recent first)
2. <a name="8.2"></a>Each meal entry SHALL display the total carbs, protein, and fat, the source (AI/manual/preset), and the timestamp
3. <a name="8.3"></a>WHEN the user expands a meal entry, THEN the app SHALL show the individual food items with their per-item macros
4. <a name="8.4"></a>The user SHALL be able to edit a saved meal (modify items, macros) and the changes SHALL persist to Cosmos DB
5. <a name="8.5"></a>The user SHALL be able to delete a saved meal and it SHALL be removed from Cosmos DB

### 9. Preset Flow Validation

**User Story:** As a user, I want to save and reuse meal presets, so that I can quickly log meals I eat frequently.

**Acceptance Criteria:**

1. <a name="9.1"></a>WHEN the user saves a meal, THEN they SHALL have the option to save it as a preset with a name and category (meal/snack)
2. <a name="9.2"></a>WHEN the user navigates to the presets page, THEN the app SHALL display all saved presets grouped by category
3. <a name="9.3"></a>WHEN the user applies a preset, THEN the app SHALL create a new meal record with the preset's items and macros (source: 'preset')
4. <a name="9.4"></a>The user SHALL be able to edit and delete presets

### 10. Label Scanning Flow Validation

**User Story:** As a user, I want to scan a nutrition label alongside my food photo, so that the AI can provide more accurate macro estimates for packaged foods.

**Acceptance Criteria:**

1. <a name="10.1"></a>WHEN the user captures a food photo, THEN the app SHALL offer the option to also capture a nutrition label photo
2. <a name="10.2"></a>WHEN both food and label photos are provided, THEN the AI endpoint SHALL process both images and use the label data to improve macro accuracy
3. <a name="10.3"></a>IF the user skips the label photo, THEN the flow SHALL proceed with food-photo-only recognition

### 11. Error Handling and Resilience

**User Story:** As a user, I want clear feedback when something goes wrong, so that I can take corrective action or use a fallback.

**Acceptance Criteria:**

1. <a name="11.1"></a>WHEN the Azure backend (Cosmos DB or Blob Storage) is unreachable, THEN the app SHALL display a clear error message indicating the service is unavailable
2. <a name="11.2"></a>WHEN the AI recognition times out (>10 seconds), THEN the app SHALL display a timeout message and offer manual entry
3. <a name="11.3"></a>WHEN image upload to Blob Storage fails, THEN the meal SHALL still be saveable without an image (macros are the priority data)
4. <a name="11.4"></a>All user-facing error messages SHALL use Irish English spelling
