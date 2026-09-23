/* Supporting screens: segmentation review, manual correction, history,
   settings, about, LiDAR-vs-no-LiDAR fork, error states */

/* Segmentation review --------------------------------------------- */
const Segmentation = () => (
  <Phone>
    <AppBar title="Review foods" left={<span className="back">‹</span>} right={<span className="hand" style={{ fontSize: 13, color: "var(--ink-3)" }}>step 2/3</span>} />
    <div className="scroll" style={{ padding: "8px 16px 16px" }}>
      <div style={{ borderRadius: 6, overflow: "hidden", border: "1px solid var(--ink-3)" }}>
        <PlateSVG variant={1} withMasks />
      </div>
      <div className="tiny muted" style={{ marginTop: 6 }}>Tap a region to confirm or relabel</div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Detected (3)</div>
      <div className="row" style={{ paddingLeft: 0, paddingRight: 0 }}>
        <div><span className="swatch" style={{ background: "rgba(45,139,95,0.5)" }}></span> White rice</div>
        <span className="chip ok"><span className="dot"></span>0.88</span>
      </div>
      <div className="row" style={{ paddingLeft: 0, paddingRight: 0 }}>
        <div><span className="swatch" style={{ background: "rgba(201,122,31,0.5)" }}></span> Roast chicken</div>
        <span className="chip"><span className="dot"></span>0.81</span>
      </div>
      <div className="row" style={{ paddingLeft: 0, paddingRight: 0 }}>
        <div><span className="swatch"></span> Broccoli</div>
        <span className="chip warn"><span className="dot"></span>0.62</span>
      </div>

      <div className="banner warn" style={{ marginTop: 12 }}>
        <span className="icon">!</span>
        <div><strong>Unrecognised region.</strong> A small area didn't match any known food and will be flagged as "unknown carbs".</div>
      </div>

      <button className="btn primary full" style={{ marginTop: 12 }}>Estimate carbs</button>
    </div>
  </Phone>
);

/* Manual correction ---------------------------------------------- */
const Correction = () => (
  <Phone>
    <AppBar title="Adjust" left={<span className="back">‹</span>} right={<span className="tiny" style={{ color: "var(--ok)" }}>Save</span>} />
    <div className="scroll" style={{ padding: "8px 16px 16px" }}>
      <div className="card">
        <div className="tiny muted">Total carbs</div>
        <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 4 }}>
          <button className="btn sm" style={{ width: 32 }}>−</button>
          <input
            defaultValue="42"
            style={{ flex: 1, fontSize: 32, textAlign: "center", border: 0, borderBottom: "1.5px solid var(--ink)", background: "transparent", fontFamily: "var(--ui)", fontWeight: 300 }}
          />
          <span className="muted">g</span>
          <button className="btn sm" style={{ width: 32 }}>+</button>
        </div>
        <div className="tiny muted" style={{ marginTop: 6 }}>was 42 g · auto-estimated</div>
      </div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Per food</div>
      {[
        { n: "White rice", g: 38, w: "65%" },
        { n: "Roast chicken", g: 0, w: "0%" },
        { n: "Broccoli", g: 4, w: "20%" },
      ].map((c, i) => (
        <div key={i} style={{ padding: "10px 0", borderBottom: "1px solid var(--ink-4)" }}>
          <div style={{ display: "flex", justifyContent: "space-between" }}>
            <span style={{ fontSize: 13 }}>{c.n}</span>
            <span style={{ fontSize: 13 }} className="mono">{c.g} g</span>
          </div>
          <div className="conf-bar" style={{ marginTop: 4 }}>
            <div className="fill" style={{ width: c.w }}></div>
          </div>
        </div>
      ))}

      <div style={{ marginTop: 14 }}>
        <div className="tiny muted">Note (optional)</div>
        <div style={{ height: 60, border: "1px dashed var(--ink-3)", borderRadius: 6, marginTop: 4, padding: 8, fontSize: 11, color: "var(--ink-3)" }}>
          e.g. "weighed rice on scale — 200 g"
        </div>
      </div>

      <div className="banner info" style={{ marginTop: 12 }}>
        Original estimate is preserved. Your correction is saved alongside it.
      </div>
    </div>
  </Phone>
);

/* Data (meal log) --------------------------------------------------
   Rows are anonymous: carbs + time + confidence only. Tap → overview. */
const History = () => (
  <Phone>
    <AppBar title="Data" left={<button className="iconbtn">⌕</button>} right={<button className="iconbtn">⊞</button>} />
    <div className="scroll">
      <div className="sect-title">Today</div>
      {[
        { time: "12:48", g: "42 g", conf: "ok", lvl: "high" },
        { time: "10:15", g: "18 g", conf: "ok", lvl: "high" },
      ].map((m, i) => (
        <div key={i} className="row">
          <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
            <div className="placeholder-img" style={{ width: 44, height: 44, borderRadius: 4 }}></div>
            <span className="meta mono" style={{ fontSize: 12 }}>{m.time}</span>
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <span className="mono" style={{ fontSize: 14, fontWeight: 500 }}>{m.g}</span>
            <span className={`chip ${m.conf}`}><span className="dot"></span>{m.lvl}</span>
            <span className="meta">›</span>
          </div>
        </div>
      ))}

      <div className="sect-title">Yesterday</div>
      {[
        { time: "19:22", g: "61 g", conf: "warn", lvl: "low" },
        { time: "13:05", g: "39 g", conf: "", lvl: "mod" },
        { time: "08:11", g: "28 g", conf: "ok", lvl: "high" },
      ].map((m, i) => (
        <div key={i} className="row">
          <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
            <div className="placeholder-img" style={{ width: 44, height: 44, borderRadius: 4 }}></div>
            <span className="meta mono" style={{ fontSize: 12 }}>{m.time}</span>
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <span className="mono" style={{ fontSize: 14, fontWeight: 500 }}>{m.g}</span>
            <span className={`chip ${m.conf}`}><span className="dot"></span>{m.lvl}</span>
            <span className="meta">›</span>
          </div>
        </div>
      ))}
    </div>
    <TabBar active="history" />
  </Phone>
);

/* Meal overview -- between Result and Segmentation review ---------- */
const MealOverview = () => (
  <Phone>
    <AppBar title="Meal" left={<span className="back">‹</span>} right={<button className="iconbtn">⋯</button>} />
    <div className="scroll" style={{ padding: "4px 16px 16px" }}>
      <div style={{ borderRadius: 6, overflow: "hidden", border: "1px solid var(--ink-3)" }}>
        <PlateSVG variant={1} withMasks />
      </div>

      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginTop: 12 }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 4 }}>
          <span style={{ fontSize: 36, fontWeight: 300, lineHeight: 1 }}>42</span>
          <span className="muted" style={{ fontSize: 13 }}>g carbs</span>
        </div>
        <span className="chip ok"><span className="dot"></span>high · 0.86</span>
      </div>
      <div className="tiny muted" style={{ marginTop: 4 }}>
        Today 12:48 · Single-view LiDAR · CoFID 2024
      </div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Foods (3)</div>
      {[
        { n: "White rice", m: "168 g · 142 cm³", g: "38 g", s: "0.88", c: "rgba(45,139,95,0.5)" },
        { n: "Roast chicken", m: "95 g · 88 cm³", g: "≈0 g", s: "0.81", c: "rgba(201,122,31,0.5)" },
        { n: "Broccoli", m: "62 g · 58 cm³", g: "4 g", s: "0.74", c: "rgba(60,60,60,0.4)" },
      ].map((f, i) => (
        <div key={i} className="row" style={{ paddingLeft: 0, paddingRight: 0 }}>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <span className="swatch" style={{ background: f.c }}></span>
            <div>
              <div style={{ fontSize: 13 }}>{f.n}</div>
              <div className="meta">{f.m}</div>
            </div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div className="mono" style={{ fontSize: 13 }}>{f.g}</div>
            <div className="meta">σ {f.s}</div>
          </div>
        </div>
      ))}

      <div style={{ display: "flex", gap: 8, marginTop: 14 }}>
        <button className="btn full">Adjust</button>
        <button className="btn primary full">Full result</button>
      </div>
    </div>
  </Phone>
);

/* Settings -------------------------------------------------------- */
const Settings = () => (
  <Phone>
    <AppBar title="Settings" left={<span className="back">‹</span>} />
    <div className="scroll">
      <div className="sect-title">Account</div>
      <div className="row disabled">
        <div>
          <div className="label">Account</div>
          <div className="meta">—</div>
        </div>
        <span className="meta">›</span>
      </div>

      <div className="sect-title">Photo &amp; data retention</div>
      <div className="row">
        <span>Keep photos for</span>
        <span className="meta">30 days ›</span>
      </div>
      <div className="row">
        <span>Delete all photos</span>
        <span className="meta" style={{ color: "var(--warn)" }}>›</span>
      </div>

      <div className="sect-title">Food database</div>
      <div className="row">
        <div>
          <div>CoFID 2024</div>
          <div className="meta">McCance &amp; Widdowson · OGL v3</div>
        </div>
        <span className="chip ok"><span className="dot"></span>active</span>
      </div>
      <div className="row">
        <div>
          <div>IFCDB 2023 overlay</div>
          <div className="meta">Irish Food Composition Database</div>
        </div>
        <div className="toggle on"></div>
      </div>

      <div className="sect-title">Capture</div>
      <div className="row">
        <span>Default path</span>
        <span className="meta">Single-view (LiDAR) ›</span>
      </div>
      <div className="row">
        <span>Always include reference card</span>
        <div className="toggle"></div>
      </div>

      <div className="sect-title">About</div>
      <div className="row"><span>Version</span><span className="meta">0.2 · research</span></div>
      <div className="row"><span>Attribution &amp; licence</span><span className="meta">›</span></div>
      <div className="row"><span>Export all data</span><span className="meta">›</span></div>
    </div>
    <TabBar active="settings" />
  </Phone>
);

/* About / Legal --------------------------------------------------- */
const About = () => (
  <Phone>
    <AppBar title="About Medata" left={<span className="back">‹</span>} />
    <div className="scroll" style={{ padding: "12px 16px 16px" }}>
      <div style={{ fontSize: 13, lineHeight: 1.5, color: "var(--ink-2)" }}>
        Medata estimates the carbohydrate content of a meal from one or two
        photographs taken on your iPhone. It runs entirely on your device —
        no photo or measurement leaves the phone.
      </div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Data sources</div>
      <div className="card">
        <div style={{ fontWeight: 500, fontSize: 13 }}>CoFID</div>
        <div className="tiny muted" style={{ marginTop: 2 }}>
          McCance &amp; Widdowson's The Composition of Foods Integrated Dataset.
          Crown Copyright. Released under Open Government Licence v3.
        </div>
      </div>
      <div className="card" style={{ marginTop: 8 }}>
        <div style={{ fontWeight: 500, fontSize: 13 }}>IFCDB (overlay)</div>
        <div className="tiny muted" style={{ marginTop: 2 }}>
          Irish Food Composition Database, optional regional overlay.
        </div>
      </div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Method</div>
      <div className="tiny muted" style={{ lineHeight: 1.5 }}>
        Estimates use shape-from-silhouette and LiDAR depth combined with
        per-class densities and bulk-correction factors calibrated against an
        internal test set. See the research spec for the full pipeline.
      </div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Legal</div>
      <div className="row" style={{ paddingLeft: 0, paddingRight: 0 }}><span>Privacy policy</span><span className="meta">›</span></div>
      <div className="row" style={{ paddingLeft: 0, paddingRight: 0 }}><span>Open-source licences</span><span className="meta">›</span></div>
      <div className="row" style={{ paddingLeft: 0, paddingRight: 0, borderBottom: 0 }}>
        <span>Not a medical device</span><span className="meta">›</span>
      </div>
    </div>
  </Phone>
);

/* LiDAR vs no-LiDAR fork ----------------------------------------- */
const LidarFork = () => (
  <Phone>
    <AppBar title="Capture" left={<span className="back">✕</span>} />
    <div className="scroll" style={{ padding: "16px 16px 8px" }}>
      <div className="banner ok">
        <span className="icon">✓</span>
        <div>
          <strong>LiDAR available.</strong>
          <div>Single photo is enough — distance and shape come from depth.</div>
        </div>
      </div>

      <div className="card" style={{ marginTop: 12, padding: 14 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
          <div>
            <div style={{ fontSize: 14, fontWeight: 500 }}>Quick (1 photo)</div>
            <div className="tiny muted" style={{ marginTop: 2 }}>~1 s · uses LiDAR depth</div>
          </div>
          <span className="chip ok"><span className="dot"></span>recommended</span>
        </div>
        <button className="btn primary full" style={{ marginTop: 10 }}>Take 1 photo</button>
      </div>

      <div className="card" style={{ marginTop: 8, padding: 14 }}>
        <div style={{ fontSize: 14, fontWeight: 500 }}>Two-view (canonical)</div>
        <div className="tiny muted" style={{ marginTop: 2 }}>~1.8 s · top-down + 25° angle. Use when LiDAR can't see the whole plate.</div>
        <button className="btn full" style={{ marginTop: 10 }}>Take 2 photos</button>
      </div>

      <div className="card" style={{ marginTop: 8, padding: 14, borderStyle: "dashed" }}>
        <div style={{ fontSize: 13, fontWeight: 500 }}>Add a reference card?</div>
        <div className="tiny muted" style={{ marginTop: 2 }}>Any ID-1 card (driving licence, bank card) included in shot improves scale confidence.</div>
        <div style={{ marginTop: 8, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span className="tiny">Include card this time</span>
          <div className="toggle"></div>
        </div>
      </div>
    </div>
  </Phone>
);

/* Errors ---------------------------------------------------------- */
const Errors = () => (
  <Phone>
    <AppBar title="Capture" left={<span className="back">✕</span>} />
    <div className="viewfinder" style={{ background: "#1a1a18" }}>
      <PlateSVG variant={1} opacity={0.4} />
      <div className="ghost-overlay" style={{ borderColor: "var(--warn)", color: "var(--warn)" }}>
        TILT 14°<br />— hold flatter
      </div>
      <div style={{ position: "absolute", top: 14, left: "50%", transform: "translateX(-50%)" }}>
        <div className="chip warn" style={{ background: "rgba(201,122,31,0.95)", color: "#fff", borderColor: "transparent" }}>
          <span className="dot"></span>too tilted
        </div>
      </div>
      <div style={{ position: "absolute", top: 50, right: 14 }}>
        <div className="bubble-level off"><div className="bubble"></div></div>
      </div>
    </div>
    <div style={{ background: "var(--paper)", padding: "12px 16px", borderTop: "1px solid var(--ink-4)" }}>
      <div style={{ fontSize: 13, fontWeight: 500 }}>Hold the phone level</div>
      <div className="tiny muted" style={{ marginTop: 2 }}>
        Top-down view needs to be within ±5° of vertical. Centre the bubble.
      </div>
      <div style={{ display: "flex", gap: 8, marginTop: 10 }}>
        <button className="btn full">Skip to 2-view</button>
        <button className="btn ghost full">Cancel</button>
      </div>
    </div>
  </Phone>
);

Object.assign(window, { Segmentation, Correction, History, MealOverview, Settings, About, LidarFork, Errors });
