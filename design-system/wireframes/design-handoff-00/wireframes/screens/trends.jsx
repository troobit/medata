/* Trends — historical graph screens
   Carbs (bars, g) + blood glucose (line, mmol/L) on a shared time axis.
   Metric include/exclude + y-scale options. */

/* --- chart geometry helpers (static wireframe data) ----------------- */
// Day view: 06:00 → 22:00 mapped to x 30..290
const glucosePts = [
  [30, 96], [50, 90], [65, 78], [80, 62], [95, 70], [115, 84],
  [135, 92], [150, 74], [165, 58], [180, 66], [200, 82], [220, 90],
  [240, 72], [255, 60], [270, 68], [290, 80],
];
const glucosePath = glucosePts.map((p, i) => `${i ? "L" : "M"}${p[0]} ${p[1]}`).join(" ");

const carbBars = [
  { x: 62, h: 34, t: "08:11" },  // breakfast 28g
  { x: 122, h: 22, t: "10:15" }, // snack 18g
  { x: 162, h: 50, t: "12:48" }, // lunch 42g
  { x: 252, h: 72, t: "19:22" }, // dinner 61g
];

const TrendChart = ({ showCarbs = true, showGlucose = true, band = true }) => (
  <svg viewBox="0 0 320 150" style={{ width: "100%", display: "block" }}>
    {/* target band 3.9–10 mmol/L */}
    {band && showGlucose && (
      <rect x="30" y="55" width="260" height="42" fill="rgba(45,139,95,0.10)" stroke="rgba(45,139,95,0.35)" strokeWidth="0.6" strokeDasharray="3 3" />
    )}
    {/* gridlines */}
    {[30, 60, 90, 120].map((y) => (
      <line key={y} x1="30" y1={y} x2="290" y2={y} stroke="#e0ded8" strokeWidth="0.8" />
    ))}
    {/* left axis (glucose) */}
    <line x1="30" y1="20" x2="30" y2="126" stroke="#c4c4c4" strokeWidth="1" />
    {/* right axis (carbs) */}
    <line x1="290" y1="20" x2="290" y2="126" stroke="#c4c4c4" strokeWidth="1" />
    {/* baseline */}
    <line x1="30" y1="126" x2="290" y2="126" stroke="#8a8a8a" strokeWidth="1" />

    {/* carb bars */}
    {showCarbs && carbBars.map((b, i) => (
      <g key={i}>
        <rect x={b.x - 6} y={126 - b.h} width="12" height={b.h}
              fill="rgba(26,26,26,0.16)" stroke="#1a1a1a" strokeWidth="1" />
      </g>
    ))}

    {/* glucose line */}
    {showGlucose && (
      <g>
        <path d={glucosePath} fill="none" stroke="#c97a1f" strokeWidth="1.6" strokeLinejoin="round" />
        {glucosePts.filter((_, i) => i % 3 === 0).map((p, i) => (
          <circle key={i} cx={p[0]} cy={p[1]} r="2.2" fill="#fafaf7" stroke="#c97a1f" strokeWidth="1.2" />
        ))}
      </g>
    )}

    {/* axis labels */}
    <text x="26" y="24" textAnchor="end" fontSize="7" fill="#8a8a8a" fontFamily="monospace">12</text>
    <text x="26" y="60" textAnchor="end" fontSize="7" fill="#8a8a8a" fontFamily="monospace">10</text>
    <text x="26" y="100" textAnchor="end" fontSize="7" fill="#8a8a8a" fontFamily="monospace">3.9</text>
    <text x="26" y="128" textAnchor="end" fontSize="7" fill="#8a8a8a" fontFamily="monospace">0</text>
    <text x="294" y="24" fontSize="7" fill="#8a8a8a" fontFamily="monospace">80g</text>
    <text x="294" y="128" fontSize="7" fill="#8a8a8a" fontFamily="monospace">0</text>
    {["06", "10", "14", "18", "22"].map((h, i) => (
      <text key={h} x={30 + i * 65} y="138" textAnchor="middle" fontSize="7" fill="#8a8a8a" fontFamily="monospace">{h}:00</text>
    ))}
    {/* unit captions */}
    <text x="30" y="12" fontSize="7" fill="#c97a1f" fontFamily="monospace">mmol/L</text>
    <text x="290" y="12" textAnchor="end" fontSize="7" fill="#1a1a1a" fontFamily="monospace">carbs g</text>
  </svg>
);

/* --- main Trends screen ---------------------------------------------- */
const Trends = () => (
  <Phone>
    <AppBar title="Trends" left={<button className="iconbtn">↧</button>} right={<button className="iconbtn">⚙</button>} />

    {/* range segmented */}
    <div style={{ display: "flex", gap: 0, margin: "0 16px 8px", border: "1px solid var(--ink-3)", borderRadius: 8, overflow: "hidden" }}>
      {["Day", "Week", "Month", "90d"].map((r, i) => (
        <div key={r} style={{
          flex: 1, textAlign: "center", padding: "6px 0", fontSize: 11,
          background: i === 0 ? "var(--ink)" : "transparent",
          color: i === 0 ? "var(--paper)" : "var(--ink-2)",
          borderRight: i < 3 ? "1px solid var(--ink-4)" : "none",
        }}>{r}</div>
      ))}
    </div>

    <div className="scroll">
      {/* date scrubber */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "2px 16px 6px", fontSize: 12 }}>
        <span className="muted">‹</span>
        <span style={{ fontWeight: 500 }}>Today · Fri 4 Jul</span>
        <span className="muted" style={{ opacity: 0.3 }}>›</span>
      </div>

      {/* chart card */}
      <div className="card" style={{ margin: "0 16px", padding: "10px 6px 6px" }}>
        <TrendChart />
      </div>

      {/* metric chips — include/exclude */}
      <div style={{ display: "flex", gap: 6, padding: "10px 16px 0", flexWrap: "wrap" }}>
        <span className="chip" style={{ borderColor: "var(--ink)", color: "var(--ink)" }}>
          <span className="dot" style={{ borderRadius: 2 }}></span>Carbs ✓
        </span>
        <span className="chip warn"><span className="dot"></span>Glucose ✓</span>
        <span className="chip" style={{ borderStyle: "dashed", color: "var(--ink-4)", borderColor: "var(--ink-4)" }}>Protein</span>
        <span className="chip" style={{ borderStyle: "dashed", color: "var(--ink-4)", borderColor: "var(--ink-4)" }}>Fat</span>
      </div>

      {/* summary stats */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, padding: "12px 16px 0" }}>
        {[
          { l: "Total carbs", v: "149 g" },
          { l: "Time in range", v: "78%" },
          { l: "Avg glucose", v: "6.8" },
        ].map((s) => (
          <div key={s.l} className="card" style={{ padding: "8px 10px" }}>
            <div className="tiny muted" style={{ fontSize: 9 }}>{s.l}</div>
            <div style={{ fontSize: 16, fontWeight: 500, marginTop: 2 }}>{s.v}</div>
          </div>
        ))}
      </div>

      {/* meals under the graph */}
      <div className="sect-title">Meals this day</div>
      {[
        { t: "Dinner", time: "19:22", g: "61 g" },
        { t: "Lunch", time: "12:48", g: "42 g" },
        { t: "Snack", time: "10:15", g: "18 g" },
        { t: "Breakfast", time: "08:11", g: "28 g" },
      ].map((m, i) => (
        <div key={i} className="row" style={{ padding: "8px 16px" }}>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <div className="placeholder-img" style={{ width: 32, height: 32, borderRadius: 4 }}></div>
            <div>
              <div style={{ fontSize: 12 }}>{m.t}</div>
              <div className="meta">{m.time}</div>
            </div>
          </div>
          <span className="mono" style={{ fontSize: 12 }}>{m.g}</span>
        </div>
      ))}
    </div>
    <TabBar active="trends" />
  </Phone>
);

/* --- graph options sheet ---------------------------------------------- */
const TrendsOptions = () => (
  <Phone>
    {/* dimmed trends behind */}
    <div style={{ position: "absolute", inset: 0, opacity: 0.25, pointerEvents: "none" }}>
      <div style={{ padding: "40px 16px" }}>
        <TrendChart />
      </div>
    </div>
    <div style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,0.25)" }}></div>

    {/* bottom sheet */}
    <div style={{
      position: "absolute", left: 0, right: 0, bottom: 0,
      background: "var(--paper)", borderRadius: "16px 16px 0 0",
      border: "1.5px solid var(--ink)", borderBottom: "none",
      padding: "8px 16px 24px", zIndex: 2,
    }}>
      <div style={{ width: 36, height: 4, background: "var(--ink-4)", borderRadius: 2, margin: "0 auto 10px" }}></div>
      <div style={{ fontSize: 15, fontWeight: 600, marginBottom: 4 }}>Graph options</div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Metrics</div>
      <div className="row" style={{ padding: "8px 0" }}>
        <div>
          <div style={{ fontSize: 13 }}>Carbs</div>
          <div className="meta">bars · from meal captures</div>
        </div>
        <div className="toggle on"></div>
      </div>
      <div className="row" style={{ padding: "8px 0" }}>
        <div>
          <div style={{ fontSize: 13 }}>Blood glucose</div>
          <div className="meta">line · from CGM / meter import</div>
        </div>
        <div className="toggle on"></div>
      </div>
      <div className="row" style={{ padding: "8px 0" }}>
        <div>
          <div style={{ fontSize: 13 }}>Target range band</div>
          <div className="meta">3.9 – 10.0 mmol/L</div>
        </div>
        <div className="toggle on"></div>
      </div>
      <div className="row disabled" style={{ padding: "8px 0" }}>
        <div>
          <div className="label" style={{ fontSize: 13 }}>Protein · Fat</div>
          <div className="meta">coming later</div>
        </div>
        <div className="toggle"></div>
      </div>

      <div className="sect-title" style={{ paddingLeft: 0 }}>Scale</div>
      <div className="row" style={{ padding: "8px 0" }}>
        <span style={{ fontSize: 13 }}>Glucose y-axis</span>
        <div style={{ display: "flex", border: "1px solid var(--ink-3)", borderRadius: 6, overflow: "hidden", fontSize: 11 }}>
          <span style={{ padding: "4px 10px", background: "var(--ink)", color: "var(--paper)" }}>Auto</span>
          <span style={{ padding: "4px 10px", color: "var(--ink-2)" }}>Fixed</span>
        </div>
      </div>
      <div className="row" style={{ padding: "8px 0", borderBottom: "none" }}>
        <span style={{ fontSize: 13 }}>Fixed max</span>
        <span className="meta mono">12 mmol/L ›</span>
      </div>

      <button className="btn primary full" style={{ marginTop: 8 }}>Done</button>
    </div>
  </Phone>
);

/* --- week view --------------------------------------------------------- */
const TrendsWeek = () => (
  <Phone>
    <AppBar title="Trends" left={<button className="iconbtn">↧</button>} right={<button className="iconbtn">⚙</button>} />
    <div style={{ display: "flex", margin: "0 16px 8px", border: "1px solid var(--ink-3)", borderRadius: 8, overflow: "hidden" }}>
      {["Day", "Week", "Month", "90d"].map((r, i) => (
        <div key={r} style={{
          flex: 1, textAlign: "center", padding: "6px 0", fontSize: 11,
          background: i === 1 ? "var(--ink)" : "transparent",
          color: i === 1 ? "var(--paper)" : "var(--ink-2)",
          borderRight: i < 3 ? "1px solid var(--ink-4)" : "none",
        }}>{r}</div>
      ))}
    </div>
    <div className="scroll">
      <div style={{ display: "flex", justifyContent: "space-between", padding: "2px 16px 6px", fontSize: 12 }}>
        <span className="muted">‹</span>
        <span style={{ fontWeight: 500 }}>28 Jun – 4 Jul</span>
        <span className="muted" style={{ opacity: 0.3 }}>›</span>
      </div>
      <div className="card" style={{ margin: "0 16px", padding: "10px 6px 6px" }}>
        <svg viewBox="0 0 320 150" style={{ width: "100%", display: "block" }}>
          {[30, 60, 90, 120].map((y) => (
            <line key={y} x1="30" y1={y} x2="290" y2={y} stroke="#e0ded8" strokeWidth="0.8" />
          ))}
          <line x1="30" y1="126" x2="290" y2="126" stroke="#8a8a8a" strokeWidth="1" />
          {/* daily carb totals — bars */}
          {[64, 88, 52, 70, 95, 60, 74].map((h, i) => (
            <rect key={i} x={44 + i * 36} y={126 - h} width="16" height={h}
                  fill="rgba(26,26,26,0.16)" stroke="#1a1a1a" strokeWidth="1" />
          ))}
          {/* avg glucose per day — line */}
          <path d="M52 70 L88 62 L124 78 L160 66 L196 54 L232 72 L268 64"
                fill="none" stroke="#c97a1f" strokeWidth="1.6" strokeLinejoin="round" />
          {["S","S","M","T","W","T","F"].map((d, i) => (
            <text key={i} x={52 + i * 36} y="138" textAnchor="middle" fontSize="7" fill="#8a8a8a" fontFamily="monospace">{d}</text>
          ))}
          <text x="30" y="12" fontSize="7" fill="#c97a1f" fontFamily="monospace">avg mmol/L</text>
          <text x="290" y="12" textAnchor="end" fontSize="7" fill="#1a1a1a" fontFamily="monospace">carbs g/day</text>
        </svg>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8, padding: "12px 16px 0" }}>
        {[
          { l: "Avg carbs/day", v: "143 g" },
          { l: "Time in range", v: "74%" },
          { l: "Meals logged", v: "26" },
        ].map((s) => (
          <div key={s.l} className="card" style={{ padding: "8px 10px" }}>
            <div className="tiny muted" style={{ fontSize: 9 }}>{s.l}</div>
            <div style={{ fontSize: 16, fontWeight: 500, marginTop: 2 }}>{s.v}</div>
          </div>
        ))}
      </div>
      <div className="banner info" style={{ margin: "12px 16px" }}>
        Glucose data imported from CGM — read-only. Medata never writes to your glucose device.
      </div>
    </div>
    <TabBar active="trends" />
  </Phone>
);

Object.assign(window, { Trends, TrendsOptions, TrendsWeek, TrendChart });
