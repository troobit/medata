/* Phone shell + shared bits used across screens */

const Phone = ({ children, time = "9:41", style }) => (
  <div className="phone" style={style}>
    <div className="statusbar">
      <span>{time}</span>
      <span className="right">
        <span style={{ fontSize: 9 }}>●●●●</span>
        <span style={{ fontSize: 9 }}>5G</span>
        <span className="icn"></span>
      </span>
    </div>
    <div className="body">{children}</div>
    <div className="home"></div>
  </div>
);

const AppBar = ({ title, left, right }) => (
  <div className="appbar">
    <div style={{ minWidth: 40 }}>{left}</div>
    <div className="title">{title}</div>
    <div style={{ minWidth: 40, display: "flex", justifyContent: "flex-end" }}>{right}</div>
  </div>
);

const TabBar = ({ active = "capture" }) => (
  <div className="tabbar">
    <div className={`tab ${active === "capture" ? "active" : ""}`}>
      <span className="gly circle">○</span>
      <span>Capture</span>
    </div>
    <div className={`tab ${active === "history" ? "active" : ""}`}>
      <span className="gly">≡</span>
      <span>Data</span>
    </div>
    <div className={`tab ${active === "trends" ? "active" : ""}`}>
      <span className="gly">∿</span>
      <span>Trends</span>
    </div>
    <div className={`tab ${active === "settings" ? "active" : ""}`}>
      <span className="gly circle">⚙</span>
      <span>Settings</span>
    </div>
  </div>
);

const Annot = ({ children, style, tone, arrow }) => (
  <div className={`annot ${tone === "warn" ? "warn-c" : tone === "ok" ? "ok-c" : ""}`} style={style}>
    {children}
    {arrow && (
      <svg
        className="arrow"
        style={arrow.style}
        width={arrow.w || 60}
        height={arrow.h || 30}
        viewBox={`0 0 ${arrow.w || 60} ${arrow.h || 30}`}
      >
        <path
          d={arrow.d}
          stroke="currentColor"
          strokeWidth="1.2"
          fill="none"
          strokeLinecap="round"
        />
        {arrow.head && (
          <path
            d={arrow.head}
            stroke="currentColor"
            strokeWidth="1.2"
            fill="none"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        )}
      </svg>
    )}
  </div>
);

/* A simple plate SVG used as a “captured” preview */
const PlateSVG = ({ variant = 1, withMasks = false, opacity = 1 }) => {
  // Draw a plate with food blobs
  const plates = {
    1: (
      <g>
        <ellipse cx="200" cy="160" rx="150" ry="80" fill="#f5f3ee" stroke="#8a8a8a" strokeWidth="1.2"/>
        <ellipse cx="200" cy="160" rx="135" ry="68" fill="none" stroke="#c4c4c4" strokeWidth="0.8"/>
        {/* rice */}
        <path d="M120 150 q10 -25 50 -22 q40 3 50 18 q5 18 -25 28 q-30 10 -55 5 q-25 -5 -20 -29z"
              fill={withMasks ? "rgba(45,139,95,0.35)" : "#ece4cf"} stroke="#3a3a3a" strokeWidth={withMasks ? 1.2 : 0.6}/>
        {/* chicken */}
        <path d="M210 145 q15 -18 38 -10 q22 8 18 28 q-4 20 -28 22 q-26 2 -32 -15 q-5 -15 4 -25z"
              fill={withMasks ? "rgba(201,122,31,0.35)" : "#d9b88b"} stroke="#3a3a3a" strokeWidth={withMasks ? 1.2 : 0.6}/>
        {/* broccoli */}
        <g>
          {[[260,170],[275,180],[268,192],[252,188],[280,168]].map(([x,y],i)=>(
            <circle key={i} cx={x} cy={y} r="6" fill={withMasks ? "rgba(60,60,60,0.4)" : "#9bb087"} stroke="#3a3a3a" strokeWidth={withMasks ? 1.2 : 0.6}/>
          ))}
        </g>
      </g>
    ),
    2: (
      <g>
        <ellipse cx="200" cy="160" rx="155" ry="85" fill="#f5f3ee" stroke="#8a8a8a" strokeWidth="1.2"/>
        <path d="M110 160 q15 -38 60 -38 q55 0 60 30 q5 28 -50 38 q-52 8 -70 -30z"
              fill={withMasks ? "rgba(45,139,95,0.35)" : "#e9dec0"} stroke="#3a3a3a" strokeWidth={withMasks ? 1.2 : 0.6}/>
        <ellipse cx="240" cy="170" rx="35" ry="22"
              fill={withMasks ? "rgba(201,122,31,0.35)" : "#c79355"} stroke="#3a3a3a" strokeWidth={withMasks ? 1.2 : 0.6}/>
      </g>
    ),
  };
  return (
    <svg viewBox="0 0 400 280" style={{ width: "100%", height: "100%", opacity }}>
      <rect width="400" height="280" fill="#2a2a28"/>
      <rect x="20" y="30" width="360" height="220" fill="#3a3a37"/>
      {plates[variant]}
    </svg>
  );
};

Object.assign(window, { Phone, AppBar, TabBar, Annot, PlateSVG });
