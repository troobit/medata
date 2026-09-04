# Getting a working LibreLink uploader for the worn sensor

The worn Libre 3+ is the user's own device, installed in their body. Reading it is their right.
Phase A of `specs/data/cgm-direct` observes an *already-active* authenticated session and reads the
value that session's owner has uploaded to LibreLinkUp — it does not itself activate or own the
sensor. So Phase A needs **some** uploader running against the sensor, but that uploader is the
user's to choose and obtain. A regional App Store restriction on Abbott's LibreLink app is a
friction to route around, **not** a terminal block.

This document is the concrete how-to for the primary route (region-matched LibreLink) and points to
the alternatives. It is referenced by `specs/data/cgm-direct` Req 10 and Decision 11, and is a
living operational note — re-verified current 2026-08-18 (region-change steps and sensor↔country
lock unchanged; US app packaging drift noted at Route A step 5); Abbott's app packaging and region
rules move, so re-verify before relying on a step.

## Why a region matters at all

Abbott publishes LibreLink as **separate, country-specific apps** on the App Store, and a Libre 3 /
3+ sensor is **locked to the LibreLink of its country of purchase** — a sensor bought in AU will not
activate or stream in, say, the US LibreLink, and vice versa. So the requirement is not "any
LibreLink" but "the LibreLink that matches where the sensor was bought." If the primary iPhone's App
Store account is in a different country from the sensor, that app simply is not offered — app
compatibility breaking on localisation.

The fix is to point the iPhone's **App Store region** at the sensor's country long enough to install
that country's LibreLink, then sign in to the same LibreView account MeData's cloud follower
(`cgm-connect`) uses.

## Route A — switch the iPhone App Store region to install the matching LibreLink

Preferred: it keeps everything on the one iPhone and needs no second device.

1. **Identify the sensor's country of purchase.** This is the country whose LibreLink you need. If
   unsure, it is the country the sensor/pharmacy invoice is from, not necessarily where the user
   lives now.
2. **Free up the current region.** Spend any App Store credit to zero and cancel active
   subscriptions — Apple refuses a region change while either is non-zero. (An Apple **Account** can
   change region; a managed/child account may be blocked — use the account that owns the device's
   App Store.)
3. **Change region:** Settings → *[your name]* → **Media & Purchases** → **View Account** →
   **Country/Region** → **Change Country or Region** → pick the sensor's country → accept the terms.
4. **Provide a compliant billing address.** Apple requires an address in the new country. LibreLink
   is free, so **Payment Method → None** is accepted once the address is in-country; a real payment
   card is not required. (A plausible in-country address is enough for a free app; keep it truthful
   where possible.)
5. **Install LibreLink** from that country's App Store. Abbott's app naming is region-dependent —
   most regions list "FreeStyle Libre 3", but the US now ships a unified **"Libre by Abbott"** app
   (App Store id 6670330506, confirmed 2026-08-18) — so match by **publisher (Abbott) and supported
   sensor**, not a fixed app name.
6. **Sign in with the LibreView account** already used for `cgm-connect` (or create one and connect
   it as the follower — see `docs/agent-notes/librelinkup-api.md`). Activate the sensor if it is not
   already active.
7. **Verify the chain end to end:** the app shows live readings → LibreView/LibreLinkUp shows the
   same → MeData's cloud follower fetches them (`cgm-connect`). Only then does the Phase A heartbeat
   have a session to observe and a cloud value to read.
8. **You may switch the App Store region back** afterwards; an installed app keeps working and
   receiving updates is not required for it to run. (If an update is ever needed, switch region back
   temporarily.) Do not delete the app while relying on it.

### Caveats

- Changing region affects the **whole** App Store account (other apps' updates, iCloud purchases).
  For a single-developer phone this is acceptable; note it before doing it.
- The sensor-to-country lock is Abbott's, not something MeData can lift in Phase A. The only route
  with **no** external uploader at all is Phase B (on-device decrypt), which is research-gated.
- None of this needs the Abbott app to keep running foregrounded — it just needs to have **activated
  the sensor and be uploading** to LibreView in the background, which is its normal behaviour.

## Route B — Juggluco bridge on an Android device

If a region-matched LibreLink cannot be installed on the iPhone (or the user prefers not to move the
iPhone's region), Juggluco on any spare Android device activates the sensor and uploads to
LibreView, restoring the `cgm-connect` cloud path with **no Abbott iOS app on the iPhone at all**.
Details and the coexistence caveat (whether the MeData heartbeat central can share an Android-held
session) are in `docs/agent-notes/libre3-direct-ble.md` and are a `cgm-direct` stream-2 research
item. Activating via Juggluco moves Abbott's realtime alarms to the Android device.

## Route C — Phase B (the real independence)

On-device decrypt with zero network and no external uploader is the only route that removes the
uploader question entirely. It is iOS-blocked today (feasibility note Blockers 1–3) and gated behind
a test sensor; it is why the direct-BLE path exists at all. Routes A and B keep Phase A working in
the meantime.

## What this is not

Not medical advice, not an endorsement to breach anyone's terms — it is documentation of how a user
reaches **their own** sensor's data through the tooling that exists, given Abbott ships LibreLink
per-region. The custody-independent goal remains Phase B.
