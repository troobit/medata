# MeData

A comprehensive personal diabetes management application for tracking meals, insulin doses, blood sugar levels, and exercise. Features AI-powered food recognition, direct CGM integration, predictive modeling, and offline-first data storage.

## Quick Start

```bash
pnpm install
pnpm dev
```

Build for production:

```bash
pnpm build
pnpm preview
```

## Core Features

### 📊 Data Logging

| Feature              | Route                                    | Description                             |
| -------------------- | ---------------------------------------- | --------------------------------------- |
| **Meal Logging**     | [/log/meal](/log/meal)                   | Manual entry with macro tracking        |
| AI Photo Recognition | [/log/meal/photo](/log/meal/photo)       | GPT-4V/Gemini/Claude vision analysis    |
| Nutrition Label Scan | [/log/meal/label](/log/meal/label)       | OCR + AI extraction from labels         |
| Volume Estimation    | [/log/meal/estimate](/log/meal/estimate) | Reference card-based portion estimation |
| Meal Presets         | [/log/meal](/log/meal)                   | Save and recall common meals            |
| **Insulin Logging**  | [/log/insulin](/log/insulin)             | Dose tracking with type & timing        |
| **BSL Entry**        | [/log/bsl](/log/bsl)                     | Manual blood sugar logging              |
| **Exercise Logging** | [/log/exercise](/log/exercise)           | Activity type, duration & intensity     |

### 📈 Data Import & Integration

| Feature              | Route                      | Description                                    |
| -------------------- | -------------------------- | ---------------------------------------------- |
| CSV Import           | [/import/bsl](/import/bsl) | Bulk import from Dexcom/Libre CSV exports      |
| CGM Graph Extraction | [/import/cgm](/import/cgm) | Extract time-series from screenshot graphs     |
| **Direct CGM API**   | [/settings](/settings)     | Real-time sync with Dexcom Share / LibreLinkUp |

**Supported CGM Integrations:**

- **Freestyle Libre** - via LibreLinkUp API (requires sharing enabled)
- **Dexcom** - via Dexcom Share API (requires sharing enabled)
- **Nightscout** - self-hosted open-source platform (planned)

### 🔮 Predictive Modeling

The app includes physiological models for blood sugar prediction:

- **Insulin Decay** - Activity curves for rapid, short, long-acting insulin types
- **Carb Absorption** - Glycemic index-based absorption modeling
- **Alcohol Metabolism** - BAL calculation and hypoglycemia risk windows
- **Circadian Patterns** - Dawn phenomenon and time-of-day insulin sensitivity
- **BSL Prediction** - Multi-factor glucose forecasting
- **Insulin Recommendations** - Meal bolus and correction dose suggestions

### 🔐 Authentication & Security

**WebAuthn/FIDO2 Support** ([/settings](/settings))

Passwordless authentication using hardware security keys (YubiKey, Titan, etc.) or platform authenticators (Touch ID, Face ID, Windows Hello).

**Current Implementation:**

- Browser-based WebAuthn API for credential registration and authentication
- Credentials stored locally in browser localStorage
- Session management with 30-day expiry
- Multi-credential support per user

**For Production Deployment with Server-Side Auth:**

To restrict deployed site access to specific YubiKey(s), you would need:

1. **Server-side WebAuthn verification** - validate authentication assertions on the server
2. **Session middleware** - verify authenticated session on every request
3. **Credential allowlist** - server-side database of authorized credential IDs
4. **HTTPS requirement** - WebAuthn requires secure context

Example flow:

```
User → Browser (WebAuthn) → Server (verify assertion) → Database (check credential allowlist)
                                     ↓
                              Issue session token
```

The current implementation handles the browser-side WebAuthn flow. For server deployment, you'd need to add:

- Backend API endpoints to verify WebAuthn assertions (using libraries like [@simplewebauthn/server](https://simplewebauthn.dev/))
- Server-side session storage (Redis, database)
- Authentication middleware to protect routes
- Environment-specific credential registration (only allow your YubiKey credential IDs)

### ✅ Validation & Testing

| Feature              | Route                                      | Description                                  |
| -------------------- | ------------------------------------------ | -------------------------------------------- |
| Validation Dashboard | [/validation](/validation)                 | Compare AI predictions against actual macros |
| Reference Capture    | [/validation/capture](/validation/capture) | Test volume estimation accuracy              |

## Tech Stack

### Frontend

- **[SvelteKit](https://kit.svelte.dev/)** - Full-stack framework with file-based routing
- **[Svelte 5](https://svelte.dev/docs/svelte/overview)** - Component framework using runes (`$state`, `$derived`, `$effect`)
- **[TypeScript](https://www.typescriptlang.org/)** - Type-safe development
- **[Tailwind CSS v4](https://tailwindcss.com/)** - Utility-first styling

### Data & Storage

- **[Dexie.js](https://dexie.org/)** - IndexedDB wrapper for local data persistence
  - Events table (meals, insulin, BSL, exercise)
  - Presets table (saved meal templates)
  - Schema: [src/lib/db/schema.ts](src/lib/db/schema.ts)
- **No server required** - all data stays on your device

### AI Integration

- **[OpenAI GPT-4 Vision](https://platform.openai.com/docs/guides/vision)** - Food recognition
- **[Google Gemini Vision](https://ai.google.dev/gemini-api/docs/vision)** - Alternative vision provider
- **[Anthropic Claude](https://www.anthropic.com/claude)** - Alternative vision provider
- API keys stored in localStorage, never sent to external servers except respective AI provider

### Authentication

- **[WebAuthn API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API)** - Browser standard for FIDO2/passkey authentication
- **[YubiKey](https://www.yubico.com/)** - Hardware security key support
- Implementation: [src/lib/services/auth/AuthService.ts](src/lib/services/auth/AuthService.ts)

### Deployment

- **[@sveltejs/adapter-vercel](https://kit.svelte.dev/docs/adapter-vercel)** - Optimized for Vercel deployment
- Static site generation (SSG) by default, API routes available if needed

## Architecture

### Directory Structure

```
src/
├── lib/
│   ├── components/              # Svelte 5 components
│   │   ├── ai/                  # AI food recognition UI
│   │   ├── cgm/                 # CGM graph extraction & display
│   │   ├── import/              # CSV import flows
│   │   ├── local-estimation/    # Volume-based macro estimation
│   │   ├── modeling/            # BSL prediction visualizations
│   │   └── ui/                  # Shared UI components (Button, Input, etc.)
│   ├── services/                # Business logic (TypeScript classes)
│   │   ├── ai/                  # AI provider integrations
│   │   ├── auth/                # WebAuthn authentication
│   │   ├── cgm/                 # CGM APIs & graph parsing
│   │   ├── import/              # CSV parsing (Dexcom/Libre)
│   │   ├── local-estimation/    # Food density & volume calculation
│   │   └── modeling/            # Physiological models & predictions
│   ├── stores/                  # Svelte 5 runes-based state
│   │   ├── events.svelte.ts     # Event data store
│   │   └── settings.svelte.ts   # User settings store
│   ├── types/                   # TypeScript interfaces
│   │   ├── events.ts            # Meal, Insulin, BSL, Exercise
│   │   ├── cgm-api.ts           # CGM integration types
│   │   ├── auth.ts              # WebAuthn types
│   │   └── validation.ts        # Validation result types
│   ├── db/                      # Dexie.js schema
│   │   └── schema.ts            # IndexedDB tables
│   └── utils/                   # Helper functions
└── routes/                      # SvelteKit file-based routing
    ├── log/                     # Logging interfaces
    ├── import/                  # Import flows
    ├── history/                 # Event timeline
    ├── validation/              # Accuracy testing
    └── settings/                # Configuration
```

### Data Flow

```
User Input → Svelte Component → Service Layer → Dexie.js → IndexedDB
                                      ↓
                              (Optional: AI API)
                              (Optional: CGM API)
```

All data processing happens client-side. External API calls only occur for:

1. AI vision analysis (user's API keys, user-initiated)
2. CGM data sync (user's CGM credentials, background sync)

### Event System

All logged data is stored as events with common metadata:

```typescript
interface BaseEvent {
  id: string; // UUID
  timestamp: Date; // When it occurred
  source: DataSource; // How it was logged
  notes?: string; // Optional user notes
}

type DataSource =
  | 'manual' // User entered
  | 'ai' // AI photo recognition
  | 'local-estimation' // Volume-based estimation
  | 'cgm-image' // Extracted from CGM screenshot
  | 'csv-import' // Imported from CSV
  | 'cgm-api'; // Direct CGM API sync
```

See [src/lib/types/events.ts](src/lib/types/events.ts) for full type definitions.

## Configuration

### API Keys (Settings Page)

Configure in [/settings](/settings):

- **OpenAI API Key** - GPT-4 Vision for food recognition
- **Google Gemini API Key** - Alternative vision provider
- **Anthropic API Key** - Alternative vision provider
- **CGM Credentials** - LibreLinkUp or Dexcom Share credentials
- **User Parameters** - ICR, ISF, target BSL, insulin types

Keys are stored in `localStorage` and never leave your device except when making API calls to the respective service.

### CGM Integration Setup

1. **Freestyle Libre (LibreLinkUp)**
   - Enable sharing in LibreLinkUp mobile app
   - Enter email/password in MeData settings
   - Select your region (US, EU, etc.)

2. **Dexcom Share**
   - Enable sharing in Dexcom app
   - Enter Share username/password
   - Select region (US or International)

3. **Auto-sync**
   - Configure sync interval (default: 5 minutes)
   - Runs in background when app is open

## Storage & Privacy

### Local-First Architecture

- **All data stored in browser IndexedDB** via Dexie.js
- **No cloud sync or external database** - your data never leaves your device
- **Offline-capable** - works without internet (except AI/CGM API features)
- **No telemetry or analytics** - completely private

### Data Persistence

| Data Type       | Storage                  | Lifespan                          |
| --------------- | ------------------------ | --------------------------------- |
| Events          | IndexedDB                | Persistent until manually deleted |
| Presets         | IndexedDB                | Persistent until manually deleted |
| Settings        | localStorage             | Persistent until manually cleared |
| Auth Sessions   | localStorage             | 30 days or until logout           |
| CGM Credentials | localStorage (encrypted) | Persistent until removed          |

### Browser Compatibility Notes

**IndexedDB Limitations:**

- **Safari Private Browsing** - IndexedDB disabled, use regular window
- **Storage Quota** - Varies by browser, typically several GB
- **iOS Safari** - Add to Home Screen for better persistence

**WebAuthn Limitations:**

- **HTTPS Required** - WebAuthn only works on `https://` or `localhost`
- **Browser Support** - Chrome 67+, Firefox 60+, Safari 13+, Edge 18+

### Troubleshooting

**"Permission denied" or "Database access blocked":**

1. Disable private/incognito mode
2. Check browser privacy settings allow site data
3. Free up device storage if quota exceeded

**Data not persisting:**

- Avoid private/incognito mode
- iOS: Use "Add to Home Screen" for better persistence
- Check browser isn't clearing site data on exit

**WebAuthn errors:**

- Ensure HTTPS (or localhost for development)
- Check browser supports WebAuthn
- Verify hardware key is inserted and working

## Development

### Commands

| Command               | Description                                 |
| --------------------- | ------------------------------------------- |
| `pnpm dev`            | Start dev server on `localhost:5173`        |
| `pnpm build`          | Build for production                        |
| `pnpm preview`        | Preview production build                    |
| `pnpm check`          | TypeScript type checking                    |
| `pnpm lint`           | Run ESLint + Prettier checks                |
| `pnpm format`         | Auto-format code with Prettier              |
| `pnpm generate-icons` | Regenerate PWA icons from `static/icon.svg` |

### Key Files

- **[svelte.config.js](svelte.config.js)** - SvelteKit configuration
- **[vite.config.ts](vite.config.ts)** - Vite build configuration
- **[tsconfig.json](tsconfig.json)** - TypeScript settings
- **[tailwind.config.ts](tailwind.config.ts)** - Tailwind configuration
- **[src/app.html](src/app.html)** - HTML template
- **[static/manifest.json](static/manifest.json)** - PWA manifest

### Adding New Features

1. **Define types** in `src/lib/types/`
2. **Create service** in `src/lib/services/`
3. **Build components** in `src/lib/components/`
4. **Add route** in `src/routes/`
5. **Update store** if needed in `src/lib/stores/`

Example: Adding a new event type

```typescript
// 1. Define type
export interface NewEvent extends BaseEvent {
  type: 'new-event';
  value: number;
}

// 2. Add to EventService
async logNewEvent(value: number): Promise<NewEvent> { ... }

// 3. Create UI component
// src/lib/components/new-event/NewEventForm.svelte

// 4. Add route
// src/routes/log/new-event/+page.svelte
```

## Backend Integrations

### IndexedDB (via Dexie.js)

The app uses [Dexie.js](https://dexie.org/) for local database management:

```typescript
// Database schema
const db = new Dexie('medata');
db.version(1).stores({
  events: 'id, timestamp, type, source',
  presets: 'id, name, updatedAt'
});
```

**Why Dexie.js?**

- Cleaner API than raw IndexedDB
- TypeScript support
- Automatic schema migrations
- Promise-based queries
- Observables for reactive updates

See [Dexie.js documentation](https://dexie.org/docs/) for query syntax and advanced features.

### AI Provider APIs

**OpenAI GPT-4 Vision**

- Endpoint: `https://api.openai.com/v1/chat/completions`
- Model: `gpt-4-turbo` or `gpt-4o`
- Docs: https://platform.openai.com/docs/guides/vision

**Google Gemini Vision**

- Endpoint: `https://generativelanguage.googleapis.com/v1/models/gemini-pro-vision:generateContent`
- Docs: https://ai.google.dev/gemini-api/docs/vision

**Anthropic Claude**

- Endpoint: `https://api.anthropic.com/v1/messages`
- Model: `claude-3-opus`, `claude-3-sonnet`
- Docs: https://docs.anthropic.com/claude/reference/messages_post

Implementation: [src/lib/services/ai/](src/lib/services/ai/)

### CGM APIs

**LibreLinkUp (Freestyle Libre)**

- Unofficial API, reverse-engineered from LibreLinkUp app
- Regional endpoints (US, EU, etc.)
- Returns glucose readings with timestamps and trends
- Implementation: [src/lib/services/cgm/LibreLinkApiService.ts](src/lib/services/cgm/LibreLinkApiService.ts)

**Dexcom Share**

- Official sharing API
- Requires Dexcom Share enabled in app
- US and International endpoints
- Implementation: [src/lib/services/cgm/DexcomShareApiService.ts](src/lib/services/cgm/DexcomShareApiService.ts)

**Nightscout**

- Open-source self-hosted platform
- REST API with token authentication
- Status: Planned, not yet implemented

### WebAuthn Authentication

The app uses the [Web Authentication API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API) for hardware key authentication:

**Registration Flow:**

1. User clicks "Register YubiKey"
2. Browser calls `navigator.credentials.create()`
3. User taps security key
4. Public key stored in localStorage
5. Session created

**Authentication Flow:**

1. User clicks "Login with YubiKey"
2. Browser calls `navigator.credentials.get()`
3. User taps security key
4. Signature verified against stored public key
5. Session created (30-day expiry)

**Multi-User Support:**

- Multiple users can register on same device
- Each user can have multiple security keys
- Credentials isolated by browser profile

**Implementation Details:**

- Service: [src/lib/services/auth/AuthService.ts](src/lib/services/auth/AuthService.ts)
- Types: [src/lib/types/auth.ts](src/lib/types/auth.ts)
- Storage: localStorage (credentials, sessions)

**Server-Side Deployment:**

For production deployment with server-side access control:

```typescript
// Example server middleware (Node.js/Express)
import { verifyAuthenticationResponse } from '@simplewebauthn/server';

// 1. Verify WebAuthn assertion
app.post('/api/auth/verify', async (req, res) => {
  const { credential, challenge } = req.body;

  // Verify signature using stored public key
  const verification = await verifyAuthenticationResponse({
    response: credential,
    expectedChallenge: challenge,
    expectedOrigin: 'https://yourdomain.com',
    expectedRPID: 'yourdomain.com',
    authenticator: storedCredential // From database
  });

  if (verification.verified) {
    // Create server-side session
    req.session.userId = userId;
    res.json({ success: true });
  }
});

// 2. Protect routes
app.use('/api/*', requireAuth);

// 3. Check credential allowlist
function requireAuth(req, res, next) {
  if (!req.session.userId) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  // Verify credential ID is in allowlist
  const credentialId = req.session.credentialId;
  if (!ALLOWED_CREDENTIALS.includes(credentialId)) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  next();
}
```

**Resources:**

- [@simplewebauthn/server](https://simplewebauthn.dev/docs/packages/server) - Server-side verification library
- [WebAuthn Guide](https://webauthn.guide/) - Protocol overview
- [Yubico Developer](https://developers.yubico.com/WebAuthn/) - YubiKey integration guide

## License

Private project - not licensed for public use.

## Support

For issues or questions, check:

- Browser console for errors
- IndexedDB viewer in DevTools
- Network tab for API call failures

This is a personal project without official support channels.
