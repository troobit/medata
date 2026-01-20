# MeData

A personal data tracking application for logging meal macros, insulin doses, and BSL. Uses ML-powered food recognition to estimate macros from photos.

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

## Features

| Feature | Route | Status |
|---------|-------|--------|
| Manual meal logging | `/log/meal` | Complete |
| AI photo recognition | `/log/meal/photo` | Complete |
| Nutrition label scan | `/log/meal/label` | Complete |
| Volume estimation | `/log/meal/estimate` | Complete |
| Insulin logging | `/log/insulin` | Complete |
| Manual BSL entry | `/log/bsl` | Complete |
| CSV BSL import | `/import/bsl` | Complete |
| CGM graph import | `/import/cgm` | Complete |
| Event history | `/history` | Complete |
| Settings | `/settings` | Complete |

## Development

### Branch Structure

```
main                    # Stable releases
└── dev-0               # Integration staging
    ├── dev-1           # Workstream A: AI food recognition (merged)
    ├── dev-2           # Workstream B: CGM graph capture (merged)
    ├── dev-3           # Workstream C: Local estimation (merged)
    └── dev-4           # Workstream D: BSL import (merged)
```

### Key Directories

```
src/
├── lib/
│   ├── components/     # Svelte components by feature
│   │   ├── ai/         # AI recognition components
│   │   ├── cgm/        # CGM graph components
│   │   ├── import/     # CSV import components
│   │   ├── local-estimation/  # Volume estimation
│   │   └── ui/         # Shared UI components
│   ├── services/       # Business logic
│   │   ├── ai/         # AI provider services
│   │   ├── cgm/        # CGM extraction
│   │   ├── import/     # CSV parsing
│   │   └── local-estimation/  # Volume calculation
│   ├── stores/         # Svelte 5 runes stores
│   ├── types/          # TypeScript interfaces
│   └── db/             # IndexedDB (Dexie)
└── routes/             # SvelteKit routes
```

### Commands

| Command | Description |
|---------|-------------|
| `pnpm dev` | Start dev server |
| `pnpm build` | Production build |
| `pnpm check` | Type checking |
| `pnpm lint` | ESLint + Prettier |
| `pnpm format` | Format code |
| `pnpm generate-icons` | Regenerate PWA icons |

## Configuration

### API Keys

Set API keys in Settings (`/settings`) for AI features:

- **OpenAI** - GPT-4 Vision for food recognition
- **Google Gemini** - Alternative vision provider
- **Anthropic Claude** - Alternative vision provider

Keys are stored in localStorage, never sent to any server except the respective AI provider.

### Data Sources

Events are tagged with their source:

| Source | Description |
|--------|-------------|
| `manual` | User entered |
| `ai` | AI photo recognition |
| `local-estimation` | Volume-based estimation |
| `cgm-image` | Extracted from CGM screenshot |
| `csv-import` | Imported from CSV file |

## Storage

All data is stored locally in IndexedDB via Dexie.js. No server or cloud account required.

### Troubleshooting

**"Permission denied" or "Database access blocked":**

1. Safari Private Browsing disables IndexedDB - use regular window
2. Check browser privacy settings allow site data
3. Free up device storage if quota exceeded

**Data not persisting:**

- Avoid private/incognito mode
- iOS Safari: use "Add to Home Screen" for better persistence

## Tech Stack

- SvelteKit + Svelte 5 (runes)
- TypeScript
- Tailwind CSS v4
- Dexie.js (IndexedDB)
- Vercel adapter

## Documentation

- [Requirements](docs/requirements.md) - Original specification
- [Development Plan](docs/DEVELOPMENT_PLAN.md) - Workstream details
