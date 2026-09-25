# `web-v0` — how the SvelteKit app on `main` was photographed

`design-system/archive/web-v0/` holds 97 frames across 28 surfaces of the SvelteKit app,
captured 2026-09-25 from `origin/main` (`adc3b56`, committed 2026-03-18). Each frame is a
PNG plus a self-contained HTML snapshot at 402x874 CSS px, `deviceScaleFactor: 3`
(1206x2622 device pixels) — the iPhone 16 Pro logical frame. `design-system/archive/README.md`
records what is in there and the two rules governing it (write-once; superseded only by a
new generation).

This note records **how** it was done, because that knowledge expires. `CLAUDE.md` says the
cycle merges `research` to `main` when the MVP work is done; after that `main` no longer
builds a SvelteKit app, and nobody can re-derive any of this by trying it. The Svelte source
survives in git; the ability to run it does not.

**None of the tooling below exists on any branch.** It lived in a throwaway extract of
`main` under `/tmp` and went with it: no Node, no `node_modules`, no build step reaches
`research`.

## The toolchain, as it stood on the day

The app still runs on current tooling. Measured on 2026-09-25:

- node **26.10.0**, pnpm **12.6.0**
- `@sveltejs/kit` **2.50.2**, `vite` **6.4.1**, `svelte` **5.49.2** — `pnpm install
  --frozen-lockfile` resolves the committed lock exactly
- `vite build` completes in about 1.5s; `vite dev` is ready in under 500ms

pnpm 12 stops the install with `ERR_PNPM_IGNORED_BUILDS` on esbuild. It is harmless —
vite works regardless. Either run `pnpm approve-builds` or ignore it; it is not the reason
anything failed.

## No backend, and no credentials

Every `+page.svelte` on `main` loads its data client-side in `$effect` via
`fetch('/api/...')`. There is no `+page.server.ts` and no `hooks.server.ts` anywhere, so
**interception happens in the browser before the request leaves** and no Azure resource is
ever contacted. `page.route()` under Playwright is the whole mechanism.

`.env.example` is misleading and cost time. It advertises `AZURE_COSMOS_CONNECTION_STRING`
and `AZURE_BLOB_STORAGE_URL`; the code imports neither. The real names are
**`PRIMARY_CONNECTION_STRING`** (`src/lib/repositories/cosmos-meal-repository.ts:8`,
`cosmos-preset-repository.ts:10`) and **`BLOB_SAS_URL`**
(`src/lib/repositories/blob-image-repository.ts:7`). `RECOGNITION_MOCK_MODE`
(`src/lib/services/recognition.ts:67`) mocks **recognition only** — it does nothing for
persistence, so setting it does not get you a working `/api/meals`. None of this matters
for capture, but it matters to anyone who starts by trying to configure the app instead of
intercepting it.

The dev server is HTTPS with a self-signed certificate — `@vitejs/plugin-basic-ssl` in
`vite.config.ts`. Any client must ignore certificate errors (`ignoreHTTPSErrors: true` on
the Playwright context). A capture that fails with a TLS error is this, not a bad URL.

## Only 4 of 28 surfaces have a URL

The catalogue's 28 web surfaces resolve to just four routes — `/`, `/capture`, `/manual`,
`/presets` — and 17 of the surfaces are components under `src/lib/components/` that no URL
reaches at all. In the run as executed, **4 surfaces were photographed through a real route
and 24 through a component harness**. A component harness is therefore not optional; it is
most of the archive.

The harness was 28 throwaway `src/routes/_harness/<surface>/+page.svelte` files, each
mounting its component with fixture props selected by a `?state=` query parameter, plus
shared fixtures at `src/lib/harness/fixtures.ts`.

**SvelteKit cannot escape the root layout from a nested one.** `+layout@.svelte` resets
**to** the root layout, not past it, so a `src/routes/_harness/+layout.svelte` saying "no
AppShell here" does nothing — the first attempt photographed every component frame nested
inside `AppShell` and the root `ToastContainer`, two levels deep, at a clipped width of
338px instead of 402px. The bypass has to be a guard in the **root** layout:

```svelte
const harness = $derived(page.url.pathname.startsWith('/_harness'));
{#if harness}{@render children()}{:else}<AppShell>{@render children()}</AppShell><ToastContainer />{/if}
```

That is why `app-shell` and `root-layout` have their own catalogue rows and their own
frames: a component photographed on its own is photographed **without** the shell, and the
shell is a separate subject.

## Determinism: freeze the clock *and* pin the timezone

The clock is frozen at `T0 = 1773835800000` = **2026-03-18T12:10:00Z**
(`page.clock.setFixedTime`). Note the value: the comment in `src/lib/harness/fixtures.ts`
originally said 12:30 and was wrong by twenty minutes; the number is what counts.

Freezing the clock is not enough. The first pass set no `timezoneId`, so every
locale-formatted timestamp rendered in the **capture machine's** zone — T0 came out as
23:10 in `LogbookList` rows and the `MealEditor` "When" field, because the machine was on
`Australia/Melbourne` (+11). Date grouping (Today / Yesterday / "Mon, 4 Aug") was still
correct, which is exactly why it was easy to miss. The context must pin both:

```js
timezoneId: 'UTC', locale: 'en-IE', colorScheme: 'dark', reducedMotion: 'reduce',
isMobile: true, hasTouch: true, ignoreHTTPSErrors: true,
viewport: { width: 402, height: 874 }, deviceScaleFactor: 3
```

An archive that is only byte-reproducible on one machine is not an archive.

## Three failures that photograph as success

These are the expensive ones. Each produced a PNG, reported `captured`, and was wrong.

**1. Playwright runs route handlers in the order opposite to registration.** A catch-all
`page.route('**/api/**', … 500)` registered *after* the per-state stubs wins every match,
and every stub is dead. Every route-mode surface then photographed its error state —
`web/home/loaded` came out as "Failed to get meals" — with no error from the driver.
Register the catch-all **first**, and have the specific stubs fall through on a method
mismatch with `route.fallback()`. Proven by isolated probe: stub-first gave
`500 {"error":"unstubbed"}`, catch-all-first gave `200 {"data":[…]}`.

Related: a leading-slash glob (`GET /api/meals/day/*`) matches nothing when the context
sets no `baseURL`, and the request falls through to the real handler. Patterns need a
`**/` prefix.

**2. Assert the intended state before photographing.** A fixture that never resolves its
data photographs as a loading spinner, and a loading spinner is a plausible-looking PNG.
Check the rendered text (or a state-specific selector) before the screenshot, not after
the run.

**3. Do not run captures concurrently against one dev server.** With several agents
creating `src/routes/_harness/<surface>/` directories while captures ran, the dev server
intermittently served **another surface's page** at a harness URL:
`recognition-error/generic.png` came back containing the preset list, and
`recognition-result/low-confidence.png` came back byte-identical to
`recognition-error/generic.png`. The page was correct every time when probed directly, so
this is a SvelteKit/Vite dev route-manifest race, not a fixture bug — and the driver
reports success. Capture **serially**. If an archive is ever re-run concurrently, check for
duplicate md5s across surfaces before trusting it.

## The four rows that cannot render on `main`

Recorded as `unrenderable` in `design-system/surfaces.md` rather than left `pending`,
because a `pending` row implies a frame somebody still owes. Nobody owes these.

| Row | Why |
| --- | --- |
| `web/capture/saving` | `isSaving` is a re-entrancy guard only. Declared `src/routes/capture/+page.svelte:52`, set `:227`, cleared `:263`, and never read by the template at `:303-380`. `MealEditor`'s `Props` (`src/lib/components/MealEditor.svelte:20-29`) has no such field, so nothing downstream could show it either. |
| `web/manual-entry/saving` | Same shape. `saving` declared `src/routes/manual/+page.svelte:22`, toggled `:52` and `:61`, never referenced in the template at `:66-79`. The screen is pixel-identical to the review state during a save. |
| `web/camera-capture/food-camera-active` | A deadlock, not a missing camera. `isCameraActive = true` is assigned once, at `src/lib/components/CameraCapture.svelte:88`, inside `if (videoRef)` at `:85`. `videoRef` is bound only by the two `<video bind:this={videoRef}>` elements at `:359` and `:385`, and both sit in branches that already require `isCameraActive` (`:356`, `:382`). On the first call `videoRef` is null, the assignment never runs, and no `<video>` is ever mounted. Measured with an instrumented probe: 4 clicks on "Open Camera", 0 `HTMLMediaElement.play()` calls, 0 `<video>` elements, 0 error banners. |
| `web/camera-capture/label-camera-active` | The same deadlock one step further in. "Add Label Photo" (`:313`) calls `startLabelCamera` (`:228`), which delegates to the same `startCamera` (`:74`) and hits the identical guard at `:85`. The branch that owns this row (`:356`) never evaluates true. |

The `archive/README.md` table gives the two camera rows the shorter reason "headless
Chromium has no camera". That is true but weaker than the measured finding above: the
viewfinder cannot render on `main` **with** a camera. The README is write-once, so the
correction lives here.

The failure is silent in the app too — the `catch` at `CameraCapture.svelte:90` only fires
on a `getUserMedia` rejection, so a *successful* `getUserMedia` leaves the user on the
chooser screen with no error at all.

## What else the run found in the frozen code

Gathered by running it, not by reading it. All of it is real behaviour on `main`, preserved
rather than fixed:

- `CameraCapture` imports `ImagePreview` (`:13`) and declares `galleryPreviewBlob` (`:47`)
  but renders neither — the gallery path goes straight from `handleFileSelect` (`:158`) to
  the label interstitial. The comment at `:46` describes a preview step that does not exist.
- `Toast` (`src/lib/components/Toast.svelte`) is `fixed bottom-20 left-1/2 -translate-x-1/2`
  with no width and no right offset, so its containing block is 402-201 = 201 logical px.
  "Delete failed" wraps onto two lines; "Mock mode active" onto three.
- `ToastContainer` does not stack: every `Toast` is fixed to the same coordinates, so
  multiple toasts pile pixel-on-pixel. On `/`, `/manual` and `/presets` it is mounted
  **twice** (`src/routes/+layout.svelte:13` and again in each page), so every toast on
  those routes renders doubled.
- `FoodRecognitionResult` has no empty-state branch (`:62-96`): an empty items array
  renders the header badge, an empty gap, a Total Macros block reading 0g/0g/0g, and a live
  "Use These Results" button that confirms an empty meal.
- `web/meal-editor/save-error` **is** renderable (`saveError` set at `MealEditor.svelte:151`,
  rendered `:219-223`) and is captured. The narrower true fact is that the `catch` at `:150`
  only sees a synchronous throw, and every caller in the app passes an async handler whose
  rejected promise it cannot see — so the state is reachable through the component's `Props`
  contract but not through any route.
- `web/image-preview/processing` is likewise renderable as a component: `isProcessing` is a
  declared prop (`ImagePreview.svelte:12`) and does reach the template (`:40`); the sole
  caller (`src/routes/capture/+page.svelte:326-330`) just never passes it.
- Several catalogue rows describe predicates that produce the same picture:
  `web/edit-meal-modal`'s four states are two (`overallConfidence` is used only in the save
  payload, never rendered), and `web/meal-editor/without-image` and `/has-items` produced
  byte-identical 137,341-byte PNGs.
- The preset update endpoint is `PUT /api/presets/<id>` (`src/lib/services/preset-api.ts:87-90`),
  not `PATCH`.
- `web/presets/loading` cannot be reached in route mode even with the stubs working:
  `loading` only flips false in the `finally` of `loadPresets`
  (`src/routes/presets/+page.svelte:44-56`), and a `route.fulfill` always settles. A loading
  state needs a request that never resolves, i.e. a client-side fetch patch — which is why
  that surface went through the harness.
- The Capture flow cannot be photographed through its real route past its pre-photo states:
  everything after `capture` needs a `Blob` that only the hidden file input
  (`CameraCapture.svelte:436`) or a live stream can supply. Any future refresh needs
  `setInputFiles` or the harness.

## `_assets/` — the things a screenshot cannot recover

`design-system/archive/web-v0/_assets/` holds `app.css`, `icon.svg`, `manifest.json` and
the four favicon files. The reason is that a PNG cannot give back a hex value. `app.css`'s
`@theme` block carries the web brand tokens — `--color-brand-accent: #63ff00`,
`--color-brand-background: #064e3b`, `--color-primary-background: #0a0a0a` — and `#064e3b`
exists nowhere else in the repo. `design-system/tokens.css` is generated from
`App/Colors.swift` and is iOS-only; it would not have preserved these.

`favicon-colour.svg` and `favicon-contrast.svg` are unreferenced alternates on `main` — two
attempts at one asset, kept side by side, predating the spec that argues for doing exactly
that.

The HTML snapshots serve the same purpose at frame level: scripts stripped, same-origin
images inlined as data URIs, so each opens by double-clicking with no server and no
requests. About 38KB each; 11MB for the archive as a whole. The only outbound references
left are the navigation `href`s, dead by design.

## What the frames are and are not evidence of

They are evidence about layout, hierarchy and colour **as Chromium rendered the web app**.
They are not evidence about how it behaved in Safari on a real iPhone, which is where the
app actually ran. And a component frame is a component on its own, without `AppShell`.
