<div align="center">

<img src="static/logo.png" alt="MeData logo" width="80" />

# MeData

[![SvelteKit](https://img.shields.io/badge/SvelteKit-Svelte_5-ff3e00?style=flat-square&logo=svelte&logoColor=white)](https://svelte.dev)
[![TailwindCSS](https://img.shields.io/badge/TailwindCSS-4-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white)](https://tailwindcss.com)

</div>

---

Personal health data tracker. SvelteKit 5, TailwindCSS 4, IndexedDB for local-first storage, PWA-ready.

## Commands

```bash
pnpm install    # Install deps + generate icons
pnpm dev        # Dev server at localhost:5173
pnpm build      # Production build
pnpm preview    # Preview production build
pnpm check      # TypeScript check
pnpm icons      # Regenerate icons from static/icon.svg
```

## Structure

```
src/routes/           # Pages (home, log, history, settings)
src/lib/components/   # UI components (Button, EmptyState, icons, etc.)
src/lib/stores/       # Svelte stores (events, settings, navigation)
src/lib/services/     # Database and API services
src/lib/types/        # TypeScript type definitions
static/icon.svg       # Logo source (generates all PWA icons)
```

## Stack

| Layer | Tech |
|-------|------|
| Framework | SvelteKit + Svelte 5 (runes) |
| Styling | TailwindCSS 4 via Vite plugin |
| Storage | IndexedDB via Dexie.js |
| Deploy | Static adapter (any static host) |

## Quick Reference

**Event types**: insulin, meal, bsl, exercise

**Icons**: Generated on install from `static/icon.svg` (gitignored)

**Brand colors**: Configured in `src/app.css` via `@theme` block

> See `CLAUDE.md` for full development guide.
