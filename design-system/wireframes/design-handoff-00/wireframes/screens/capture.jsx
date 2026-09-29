/* Capture flow variations — 3 approaches */

/* Variation A: Sequential — clear two-step but optimized for single-view LiDAR */
const CaptureA = () => (
  <Phone>
    <AppBar
      title="New meal"
      left={<span className="back">✕</span>}
      right={<button className="iconbtn">?</button>}
    />
    <div className="steps">
      <div className="seg active"></div>
      <div className="seg"></div>
    </div>
    <div className="viewfinder">
      <PlateSVG variant={1} />
      <div className="reticle"></div>
      <div className="vf-hint" style={{ top: 14 }}>Top-down · 30–40 cm</div>
      <div style={{ position: "absolute", top: 50, right: 14 }}>
        <div className="bubble-level"><div className="bubble"></div></div>
      </div>
      <div style={{ position: "absolute", bottom: 14, left: 14, fontSize: 10, fontFamily: "var(--mono)", color: "#fff" }}>
        <div>tilt 1.8°</div>
        <div>dist 34 cm</div>
        <div style={{ color: "#2d8b5f" }}>● LiDAR</div>
      </div>
      <div className="vf-hint" style={{ bottom: 14, left: "50%" }}>Hold steady — capturing nadir view</div>
    </div>
    <div className="shutter-area">
      <div className="shutter-side">2-VIEW</div>
      <div className="shutter"></div>
      <div className="shutter-side">FLASH</div>
    </div>
  </Phone>
);

/* Variation B: Combined / progressive — single tap, app guides through both */
const CaptureB = () => (
  <Phone>
    <AppBar
      title="Capture"
      left={<span className="back">✕</span>}
      right={<span className="hand" style={{ fontSize: 13, color: "var(--ink-3)" }}>1 / 2</span>}
    />
    <div className="viewfinder">
      <PlateSVG variant={1} />
      <div className="ghost-overlay">
        ALIGN PLATE WITHIN
        <br />
        OUTLINE
      </div>
      <div className="vf-hint" style={{ top: 14 }}>Move closer · ID-1 card optional</div>
      <div style={{ position: "absolute", bottom: 70, left: 0, right: 0, textAlign: "center" }}>
        <div className="chip ok" style={{ background: "rgba(45,139,95,0.85)", color: "#fff", borderColor: "transparent" }}>
          <span className="dot"></span>Plate detected
        </div>
      </div>
    </div>
    <div className="shutter-area" style={{ flexDirection: "column", padding: "12px 24px 12px", gap: 8 }}>
      <div style={{ fontSize: 11, color: "var(--ink-2)", textAlign: "center" }}>
        Tap once — we'll guide you through the second angle if needed.
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", width: "100%", alignItems: "center" }}>
        <div className="shutter-side">↺</div>
        <div className="shutter"></div>
        <div className="shutter-side">i</div>
      </div>
    </div>
  </Phone>
);

/* Variation C: Confidence-gated — minimal chrome, captures when geometry is right */
const CaptureC = () => (
  <Phone>
    <div style={{ position: "absolute", top: 32, left: 0, right: 0, padding: "10px 16px", display: "flex", justifyContent: "space-between", zIndex: 5, color: "#fff" }}>
      <span style={{ fontSize: 22 }}>✕</span>
      <span style={{ fontSize: 13, fontFamily: "var(--mono)" }}>NADIR</span>
      <span style={{ fontSize: 13 }}>?</span>
    </div>
    <div className="viewfinder" style={{ flex: 1 }}>
      <PlateSVG variant={2} />
      <div style={{ position: "absolute", top: "50%", left: "50%", transform: "translate(-50%,-50%)" }}>
        <div className="dial"><span className="label">2°</span></div>
      </div>
      <div style={{ position: "absolute", bottom: 90, left: 0, right: 0, textAlign: "center" }}>
        <div style={{ fontSize: 13, color: "#fff", fontWeight: 500 }}>Almost level</div>
        <div style={{ fontSize: 10, color: "rgba(255,255,255,0.7)", marginTop: 2 }}>auto-capture in 2…</div>
      </div>
      <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, padding: "8px 16px", background: "rgba(0,0,0,0.4)", display: "flex", justifyContent: "space-between", fontSize: 10, fontFamily: "var(--mono)", color: "#fff" }}>
        <span>tilt 2.0°</span>
        <span>dist 36cm</span>
        <span style={{ color: "#2d8b5f" }}>LiDAR ✓</span>
        <span>card —</span>
      </div>
    </div>
    <div style={{ padding: "12px 16px", background: "var(--paper)", display: "flex", justifyContent: "space-between", alignItems: "center", flexShrink: 0 }}>
      <span className="tiny muted">auto</span>
      <div className="shutter" style={{ width: 50, height: 50 }}></div>
      <span className="tiny muted">manual</span>
    </div>
  </Phone>
);

Object.assign(window, { CaptureA, CaptureB, CaptureC });
