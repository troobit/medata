<div align="center">

<img src="static/logo.png" alt="MeData logo" width="80" />

# MeData

[![SvelteKit](https://img.shields.io/badge/SvelteKit-Svelte_5-ff3e00?style=flat-square&logo=svelte&logoColor=white)](https://svelte.dev)
[![TailwindCSS](https://img.shields.io/badge/TailwindCSS-4-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white)](https://tailwindcss.com)
[![Deploy](https://img.shields.io/badge/Deploy-Vercel-black?style=flat-square&logo=vercel&logoColor=white)](https://vercel.com)

</div>

---

Personal health data tracker with AI-powered food recognition. SvelteKit 5, TailwindCSS 4, IndexedDB for local-first storage, PWA-ready.

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

| Layer     | Tech                             |
| --------- | -------------------------------- |
| Framework | SvelteKit + Svelte 5 (runes)     |
| Styling   | TailwindCSS 4 via Vite plugin    |
| Storage   | IndexedDB via Dexie.js           |
| AI        | Cloud Vision APIs (configurable) |
| Deploy    | Vercel (auto-deploy on merge)    |

## Quick Reference

**Event types**: insulin, meal, bsl, exercise

**Icons**: Generated on install from `static/icon.svg` (gitignored)

**Brand colors**: Configured in `src/app.css` via `@theme` block

## Research References

The AI food recognition approach is informed by peer-reviewed research:

| Paper                                                                                                                                                 | Key Findings                                                                                                                |
| ----------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| [GoCARB: Carbohydrate Estimation by Mobile Phone (JMIR 2016)](https://www.jmir.org/2016/5/e101/)                                                      | Mobile carbohydrate estimation achieves 26.9% mean absolute error vs 34.3% for self-report; 85.1% food recognition accuracy |
| [Comprehensive Survey of Image-Based Food Recognition (Healthcare 2021)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8700885/)                           | Survey of CNN architectures for food recognition; MobileNetV2 achieves ~85% on Food-101                                     |
| [Smartphone-based Food Recognition with Multiple CNN Models (MTA 2021)](https://link.springer.com/article/10.1007/s11042-021-11329-6)                 | Ensemble deep learning approaches for mobile food classification                                                            |
| [Applying Image-Based Food-Recognition Systems (Advances in Nutrition 2023)](<https://advances.nutrition.org/article/S2161-8313(23)00093-5/fulltext>) | Systematic review of dietary assessment accuracy across platforms                                                           |
| [AI-based Digital Image Dietary Assessment (Annals of Medicine 2023)](https://www.tandfonline.com/doi/full/10.1080/07853890.2023.2273497)             | Comparison of AI methods to human assessment and ground truth                                                               |

### Key Research Insights

1. **User corrections improve accuracy**: Systems that capture user edits to AI predictions can iteratively improve (GoCARB approach)
2. **Cloud APIs outperform on-device**: Modern vision APIs (GPT-4V, Gemini, Claude) exceed accuracy of standalone mobile models
3. **Reference objects aid volume estimation**: Known-size objects (credit card, coin) improve portion size accuracy
4. **Carb estimation is harder than recognition**: Identifying food is easier than accurately estimating macros from images

> See `docs/DEVELOPMENT_PLAN.md` for implementation details.

---

> See `CLAUDE.md` for full development guide.
