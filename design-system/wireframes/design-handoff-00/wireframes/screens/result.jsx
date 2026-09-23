/* Result screen variations — 3 layouts */

const ConfChip = ({ level }) => {
  const map = {
    high: { tone: "ok", label: "High confidence", val: "0.86" },
    med: { tone: "", label: "Moderate confidence", val: "0.71" },
    low: { tone: "warn", label: "Uncertain", val: "0.54" },
  };
  const c = map[level];
  return (
    <span className={`chip ${c.tone}`}>
      <span className="dot"></span>
      {c.label} · {c.val}
    </span>
  );
};

const classes = [
  { name: "White rice", g: 38, mass: 168, conf: 0.88, vol: 142 },
  { name: "Roast chicken", g: 0, mass: 95, conf: 0.81, vol: 88, note: "≈0 g carbs" },
  { name: "Broccoli", g: 4, mass: 62, conf: 0.74, vol: 58 },
];

/* Variation A: Single-number hero */
const ResultA = () => (
  <Phone>
    <AppBar
      title="Estimate"
      left={<span className="back">‹</span>}
      right={<button className="iconbtn">⋯</button>}
    />
    <div className="scroll" style={{ padding: "8px 16px 16px" }}>
      <div style={{ textAlign: "center", padding: "20px 0 8px" }}>
        <div className="hero-num">42<span className="unit">g carbs</span></div>
        <div style={{ marginTop: 12 }}><ConfChip level="high" /></div>
        <div className="tiny muted" style={{ marginTop: 6 }}>
          Today, 12:48 · Single-view LiDAR
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
          <div className="placeholder-img" style={{ width: 64, height: 48, borderRadius: 4 }}>photo</div>
          <div style={{ flex: 1, fontSize: 11, color: "var(--ink-2)" }}>
            <div>3 foods recognised</div>
            <div className="muted">Total mass 325 g · ~580 kJ</div>
          </div>
        </div>
      </div>

      <div className="sect-title" style={{ padding: "16px 0 4px" }}>Per-class breakdown</div>
      {classes.map((c, i) => (
        <div className="class-row" key={i}>
          <div>
            <div className="name"><span className="swatch"></span>{c.name}</div>
            <div className="meta">{c.mass} g · vol {c.vol} cm³</div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div className="val">{c.note || `${c.g} g`}</div>
            <div className="meta">σ {c.conf.toFixed(2)}</div>
          </div>
        </div>
      ))}

      <div style={{ display: "flex", gap: 6, marginTop: 10 }}>
        <span className="chip" style={{ borderStyle: "dashed", color: "var(--ink-4)", borderColor: "var(--ink-4)" }}>Protein — soon</span>
        <span className="chip" style={{ borderStyle: "dashed", color: "var(--ink-4)", borderColor: "var(--ink-4)" }}>Fat — soon</span>
      </div>

      <button className="btn full" style={{ marginTop: 16 }}>Adjust manually</button>
      <button className="btn primary full" style={{ marginTop: 8 }}>Save to history</button>
    </div>
  </Phone>
);

/* Variation B: Breakdown-first */
const ResultB = () => (
  <Phone>
    <AppBar
      title="Lunch"
      left={<span className="back">‹</span>}
      right={<button className="iconbtn">⋯</button>}
    />
    <div className="scroll">
      <div style={{ padding: "8px 16px 8px", display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
        <div>
          <div className="tiny muted">CARBS</div>
          <div style={{ fontSize: 32, fontWeight: 500, lineHeight: 1, marginTop: 2 }}>42 g</div>
        </div>
        <ConfChip level="high" />
      </div>

      <div style={{ padding: "0 16px" }}>
        <div className="placeholder-img" style={{ aspectRatio: "16/9", borderRadius: 6, marginTop: 4 }}>nadir capture · 1 view · LiDAR</div>
      </div>

      <div className="sect-title">Foods detected</div>
      {classes.map((c, i) => (
        <div key={i} style={{ padding: "10px 16px", borderBottom: "1px solid var(--ink-4)" }}>
          <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
            <span style={{ fontSize: 13, fontWeight: 500 }}>{c.name}</span>
            <span style={{ fontSize: 13, fontVariantNumeric: "tabular-nums" }}>{c.note || `${c.g} g`}</span>
          </div>
          <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
            <div className="conf-bar" style={{ flex: 1 }}>
              <div className="fill" style={{ width: `${c.conf * 100}%` }}></div>
            </div>
            <span className="tiny muted mono">{c.mass}g · σ{c.conf.toFixed(2)}</span>
          </div>
        </div>
      ))}

      <div style={{ padding: "12px 16px", display: "flex", gap: 8 }}>
        <button className="btn full">Adjust</button>
        <button className="btn primary full">Save</button>
      </div>
    </div>
  </Phone>
);

/* Variation C: Confidence-led — leads with how trustworthy this is */
const ResultC = () => (
  <Phone>
    <AppBar title="Estimate" left={<span className="back">‹</span>} />
    <div className="scroll">
      <div style={{ padding: "12px 16px" }}>
        <div className="banner warn" style={{ marginBottom: 12 }}>
          <span className="icon">!</span>
          <div>
            <strong>Moderate confidence (0.71)</strong>
            <div style={{ marginTop: 2 }}>One class seen in only one view. Tap any item to override.</div>
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginBottom: 4 }}>
          <span style={{ fontSize: 48, fontWeight: 300, lineHeight: 1 }}>42</span>
          <span className="muted" style={{ fontSize: 14 }}>g carbs · ± 8 g range</span>
        </div>
        <div className="conf-bar warn" style={{ height: 8 }}>
          <div className="fill" style={{ width: "71%" }}></div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 4 }} className="tiny muted">
          <span>scale 0.85</span><span>seg 0.81</span><span>geom 0.75</span>
        </div>
      </div>

      <div className="sect-title">What we detected</div>
      {classes.map((c, i) => (
        <div className="row" key={i} style={{ padding: "10px 16px" }}>
          <div>
            <div style={{ fontSize: 13 }}>{c.name}</div>
            <div className="meta">{c.mass} g · {c.vol} cm³</div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div style={{ fontSize: 13, fontVariantNumeric: "tabular-nums" }}>{c.note || `${c.g} g`}</div>
            <div className="meta">tap to edit ›</div>
          </div>
        </div>
      ))}

      <div style={{ padding: 12, display: "flex", gap: 8 }}>
        <button className="btn full">Retake</button>
        <button className="btn primary full">Save</button>
      </div>
    </div>
  </Phone>
);

Object.assign(window, { ResultA, ResultB, ResultC, ConfChip });
