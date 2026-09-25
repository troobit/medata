# Archive

Frozen captures of how the app looked at one moment. Two rules, and they are the whole point:

1. **Write-once.** Nothing under `archive/` is ever edited in place. A file nobody may edit cannot drift;
   it is a record of a moment, not a description of the present.
2. **Superseded only by a new generation.** When the app changes enough to be worth re-photographing, a new
   `-vN` directory is added beside the old one. The old one stays.

`N` is a generation counter, not a version number. Everything stays `v0` until `research` merges to `main`
(`docs/agent-notes/device-build-and-test.md`, "Everything stays v0 until main").

What is *current* lives elsewhere: `design-system/surfaces.md` answers what surfaces and states exist right
now. The archive only answers what generation N looked like.

---

## Generations

| Generation | What it holds | Status |
| --- | --- | --- |
| `web-v0/` | The SvelteKit app on `main` — 97 frames across 28 surfaces, PNG + HTML | complete |
| `ios-v0/` | The SwiftUI app on `research` | not yet captured; needs the device |
| `pages-v0/` | The 14 prose pages of `design-system/pages/`, frozen verbatim | not yet frozen |

---

## `web-v0/` — the SvelteKit app on `main`

The web app is the generation that expires. `CLAUDE.md` says the cycle "currently runs along the 'research'
branch, with intent to merge to main when the MVP work is done", and once that happens the SvelteKit
toolchain is no longer the thing `main` builds. The Svelte source survives in git either way; what expired
was the ability to *run* it and photograph the screens. That capture has now been taken.

**Captured 2026-09-25** from `origin/main` (`adc3b56`, committed 2026-03-18), on node 26.10.0 / pnpm 12.6.0,
`@sveltejs/kit` 2.50.2, `vite` 6.4.1, `svelte` 5.49.2, via headless Chromium under Playwright.

### What is here

- `<surface>/<state>.png` — the frame, at iPhone 16 Pro logical metrics: 402x874 CSS px at
  `deviceScaleFactor: 3`, i.e. 1206x2622 device pixels, the same frame the phone produces.
- `<surface>/<state>.html` — the same frame as static HTML. A PNG records what the screen looked like but
  cannot be measured, and a hex value cannot be recovered from it. The snapshot keeps the numbers. Scripts
  are stripped and same-origin images are inlined as data URIs, so it opens by double-clicking with no
  server and no requests. The only outbound references left are the navigation `href`s, which are dead by
  design — this is a frozen app.
- `_assets/` — the files a screenshot cannot recover: `app.css` (whose `@theme` block carries the web brand
  tokens `--color-brand-accent: #63ff00`, `--color-brand-background: #064e3b` and
  `--color-primary-background: #0a0a0a`; `#064e3b` exists nowhere else in the repo), `icon.svg`,
  `manifest.json`, and the three favicon variants. `favicon-colour.svg` and `favicon-contrast.svg` are
  unreferenced alternates on `main` — a ready-made instance of the two-attempts convention, predating the
  spec that argues for it.

### How the capture was made, and what that means for trusting it

No Azure backend was involved and none is needed. The app's API calls were intercepted in the browser
before the request left, and fulfilled from fixtures; anything not explicitly stubbed was failed with a 500
so that a missing fixture shows up as an error state rather than silently reaching a real service. The
clock was frozen at `2026-03-18T12:10:00Z` and the timezone pinned to UTC, so every rendered timestamp is
reproducible rather than dependent on the machine that ran the capture.

Four of the 28 surfaces are routes; the other 24 are components that no URL reaches. Those were rendered
through a throwaway harness that mounted each component with fixture props. **None of that tooling exists
on any branch.** It lived in a `git archive` extract of `main` under `/tmp` and went with it: no Node, no
`node_modules`, no build step reaches `research`.

Two consequences worth stating plainly. The frames are evidence about layout, hierarchy and colour as the
web app rendered them in Chromium — not about how they behaved in Safari on a real iPhone, which is where
this app actually ran. And a component photographed on its own is photographed **without** `AppShell`,
because `app-shell` and `root-layout` have their own rows and their own frames.

### Coverage

97 of the catalogue's 101 `web-v0` rows are captured. The other four describe states that **cannot render
on `main`** — in each case a flag exists in the script block but never reaches the template, so the state
was reachable in the author's intent and never on screen:

| Row | Why it cannot render |
| --- | --- |
| `web/capture/saving` | `isSaving` is a re-entrancy guard only — `src/routes/capture/+page.svelte:52`, set `:227`, never read by the template at `:303-380`, and `MealEditor`'s props have no such field |
| `web/manual-entry/saving` | `saving` declared `src/routes/manual/+page.svelte:22`, toggled `:52`/`:61`, never passed to the template |
| `web/camera-capture/food-camera-active` | `isCameraActive = true` requires a live `getUserMedia` stream; headless Chromium has no camera, and the state is unreachable without one |
| `web/camera-capture/label-camera-active` | same |

These are recorded as `unrenderable` in `design-system/surfaces.md` rather than left `pending`, because a
`pending` row implies a frame somebody still owes. Nobody owes these.
