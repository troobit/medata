# Settings — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §12 Settings screen.

**Brief:** Capture defaults and data controls in one place, out of the capture
flow. Matches shipped reality, not the handoff's stale items: CoFID + AFCD (not
IFCDB), and no photo-retention controls (Decision 4).

---

## Layout

```
┌─────────────────────────────────────┐
│  Settings                           │
│  Account                        (disabled)
│                                      │
│  FOOD DATABASE                      │
│  CoFID                              │
│  AFCD                               │
│                                      │
│  CAPTURE                            │
│  Default path        [1-view│2-view] │
│  Always include card            (on) │
│                                      │
│  Export                            ↑ │
│  About                            ›  │
│  Seed demo glucose        (DEBUG only)
└─────────────────────────────────────┘
```

---

## Specifics

- **Container:** system `Form`, title `Settings`, inside the Settings sheet's
  `NavigationStack`.
- **Account (§12.1):** a disabled `Account` row (placeholder for a future sign-in).
- **Food database (§12.2):** section `Food database` naming the actually bundled
  editions — `CoFID` and `AFCD` (CoFID-wins merge). **Not IFCDB** (Decision 4).
- **Capture (§12.1/§12.4):** `Default path` picker `1-view` / `2-view` writing
  `SettingsKeys.captureMode` (`.single` / `.double`); `Always include card` toggle
  on `SettingsKeys.alwaysIncludeCard`. Both persist unchanged.
- **Export (§12.4):** `Export` runs `store.exportArchive()` and shares the
  resulting archive.
- **About (§13):** a `NavigationLink` to About — attribution now lives there, not
  inline in Settings.
- **Seed demo glucose (Decision 13):** a `#if DEBUG`-only `Seed demo glucose` row
  calling `seedDemoBslEvents()` so Trends is verifiable before an importer ships.
  Never compiled into Release.
- **No retention (§12.3):** there are no photo-retention controls; photo lifecycle
  is delegated to the user's Photos library.

---

## Anti-patterns

- Do NOT name IFCDB or add a database-source override (Decision 4).
- Do NOT add photo-retention controls (Req 12.3).
- Do NOT keep attribution inline here — it belongs in About.
- Do NOT let the DEBUG seed row leak into Release.
