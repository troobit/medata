# LibreLinkUp API contract (cgm-connect task 7 spike, 2026-07-10)

Unofficial follower API used by the `LibreLinkUpGlucoseSource`. Verdict: **contract confirmed — implementable with reasonable confidence.** Cross-checked against three independently maintained open-source clients: nightscout-librelink-up (release 3.3.0, March 2026), pylibrelinkup, and DiaKEM libre-link-up-api-client. Expect roughly yearly header churn from Abbott; every break so far was fixed by bumping a header value.

## Common headers (all requests)

```
product: llu.ios
version: 4.16.0            // config constant; see version-churn below
Content-Type: application/json;charset=UTF-8
User-Agent: <iPhone-ish UA>
```

## Auth flow

- `POST https://api-eu.libreview.io/llu/auth/login` with `{"email": "...", "password": "..."}` (credentials from Keychain).
- `status == 0` with `data.redirect == true` → re-login at `https://api-{data.region}.libreview.io`; persist the resolved host. Known hosts: `api` (global), `api-eu`, `api-eu2`, `api-de`, `api-fr`, `api-us`, `api-ca`, `api-au`, `api-ap`, `api-ae`, `api-jp`, `api-la` (all `.libreview.io`). Ireland lands on `api-eu`.
- `status == 4` → account step pending (`data.step.type`: `tou` / `pp` / `verifyEmail`). Do not automate; surface "complete this in the LibreLinkUp app" (community clients do the same).
- Success → `data.authTicket.token` (JWT bearer, ~6-month validity via `data.authTicket.expires`, Unix seconds) and `data.user.id`.
- Authenticated requests add: `Authorization: Bearer {token}` and `account-id: {SHA-256 hex of data.user.id}` (enforced since LLU 4.11, 2024).

## Fetching readings

- `GET {host}/llu/connections` → `data[]` of followed patients (`patientId`, names, latest `glucoseMeasurement`).
- `GET {host}/llu/connections/{patientId}/graph` → `data.connection.glucoseMeasurement` (latest, refreshes ~every minute) + `data.graphData[]` (~12 h of history; community reports vary between 5- and 15-minute buckets).
- Reading fields: `FactoryTimestamp` (UTC) and `Timestamp` (patient-local), both `"M/d/yyyy h:mm:ss a"` — parse with `en_US_POSIX`, TZ pinned to UTC for FactoryTimestamp; `ValueInMgPerDl` (Int); `Value` + `GlucoseUnits` (display unit — ignore, the unit-flag mapping is not formally documented); `isHigh` / `isLow`; latest measurement also carries `TrendArrow`.
- **Units**: read only `ValueInMgPerDl` and convert in-app (÷ 18.0182 → mmol/L, one decimal). This sidesteps the `GlucoseUnits` flag ambiguity and matches nightscout's approach.
- **No stable per-reading id.** Dedup key is `(patientId, FactoryTimestamp)` — sensor-derived and stable across polls. `nativeID` for `GlucoseSample` should be nil or the FactoryTimestamp string.

## Failure modes and limits

- Rate limiting: Cloudflare 1015 / HTTP 429–430 with `Retry-After`. 3-minute polling has caused account bans; nightscout's 5-minute default works at scale. The spec's ≤15-minute poll is comfortably safe.
- Version floor bumps (~yearly: 4.7 → 4.11 → 4.16.0): failure is self-describing — HTTP 403 with `{"data":{"minimumVersion":"…"},"status":920}`. Detect status 920 and surface "update needed" (or retry with the advertised minimum).
- 401 → re-login once with stored credentials; repeated failure → `.failed` connection state.
- Keep `version` and the base URL as easily updated constants.

Sources: nightscout-librelink-up `src/index.ts` + `llu-api-endpoints.ts`, khskekec HTTP dump gist, pylibrelinkup source, DiaKEM `client.ts`.
