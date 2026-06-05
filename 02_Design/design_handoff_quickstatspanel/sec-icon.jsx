// sec-icon.jsx — Prompt 5: macOS app icon, three directions.

// macOS squircle icon shell with bevel. size in px.
function IconShell({ size = 168, children, bg }) {
  const r = Math.round(size * 0.2237); // macOS continuous-corner ratio (approx)
  return (
    <div style={{ position: 'relative', width: size, height: size }}>
      <div style={{ position: 'absolute', inset: 0, borderRadius: r, background: bg, overflow: 'hidden',
        boxShadow: `0 ${size*0.06}px ${size*0.14}px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.18), inset 0 -1px 0 rgba(0,0,0,0.4)` }}>
        {/* top sheen */}
        <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '46%',
          background: 'linear-gradient(rgba(255,255,255,0.12), rgba(255,255,255,0))' }} />
        {children}
      </div>
      {/* hairline ring */}
      <div style={{ position: 'absolute', inset: 0, borderRadius: r, boxShadow: 'inset 0 0 0 1px rgba(255,255,255,0.08)' }} />
    </div>
  );
}

const ICON_BG = 'linear-gradient(158deg, #2b3340 0%, #1a1e27 52%, #0e1014 100%)';
const ICON_ACCENT = 'oklch(0.78 0.13 175)';   // cyan-green "live data"
const ICON_ACCENT2 = 'oklch(0.80 0.14 92)';   // amber spark

// 1 · Literal — a tiny stat strip
function IconLiteral({ size = 168 }) {
  const u = size / 168;
  const cells = [[0.5, 0.78], [0.62, 0.5], [0.44, 0.9], [0.7, 0.4]];
  return (
    <IconShell size={size} bg={ICON_BG}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'stretch', height: 64 * u, padding: `0 ${4*u}px`,
          background: 'rgba(255,255,255,0.07)', border: `${1.4*u}px solid rgba(255,255,255,0.18)`,
          borderRadius: 13 * u, backdropFilter: 'blur(2px)', boxShadow: `0 ${4*u}px ${10*u}px rgba(0,0,0,0.4)` }}>
          {cells.map((c, i) => (
            <React.Fragment key={i}>
              {i > 0 && <span style={{ width: 1, background: 'rgba(255,255,255,0.14)', margin: `${10*u}px 0` }} />}
              <span style={{ width: 26 * u, display: 'flex', flexDirection: 'column', justifyContent: 'center',
                alignItems: 'center', gap: 5 * u }}>
                <span style={{ width: 12 * u, height: 12 * u, borderRadius: 3 * u,
                  background: i === 2 ? ICON_ACCENT2 : ICON_ACCENT, opacity: 0.92 }} />
                <span style={{ width: 16 * u, height: 4 * u, borderRadius: 2 * u, background: 'rgba(255,255,255,0.85)' }} />
              </span>
            </React.Fragment>
          ))}
        </div>
      </div>
    </IconShell>
  );
}

// 2 · Abstract — data motif (bars + baseline)
function IconAbstract({ size = 168 }) {
  const u = size / 168;
  const bars = [0.42, 0.66, 0.5, 0.86, 0.62];
  return (
    <IconShell size={size} bg={ICON_BG}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', gap: 11 * u }}>
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8 * u, height: 70 * u }}>
          {bars.map((h, i) => (
            <span key={i} style={{ width: 13 * u, height: `${h * 100}%`, borderRadius: 5 * u,
              background: `linear-gradient(${ICON_ACCENT}, color-mix(in oklab, ${ICON_ACCENT} 60%, #1a1e27))`,
              boxShadow: `0 0 ${10*u}px -2px ${ICON_ACCENT}` }} />
          ))}
        </div>
        <span style={{ width: 92 * u, height: 6 * u, borderRadius: 3 * u, background: 'rgba(255,255,255,0.9)' }} />
      </div>
    </IconShell>
  );
}

// 3 · Symbolic — slim bar summoned at speed (trailing ghosts + spark)
function IconSymbolic({ size = 168 }) {
  const u = size / 168;
  const bar = (op, dx, w) => <span style={{ position: 'absolute', left: '50%', top: '50%',
    width: w * u, height: 26 * u, borderRadius: 7 * u, transform: `translate(calc(-50% + ${dx*u}px), -50%)`,
    background: op === 1 ? 'rgba(255,255,255,0.95)' : `rgba(255,255,255,${op})` }} />;
  return (
    <IconShell size={size} bg={ICON_BG}>
      <div style={{ position: 'absolute', inset: 0 }}>
        {bar(0.16, -34, 60)}
        {bar(0.34, -20, 72)}
        {bar(1, 4, 96)}
        {/* spark */}
        <span style={{ position: 'absolute', left: '50%', top: '50%', transform: `translate(${52*u}px, -50%)`,
          color: ICON_ACCENT2, display: 'flex' }}>
          <svg width={26*u} height={26*u} viewBox="0 0 16 16" fill="currentColor"><path d="M9 1L3.5 9H7l-.8 6L13 6.5H8.6L9 1z"/></svg>
        </span>
      </div>
    </IconShell>
  );
}

function IconCase({ title, tag, note, Comp }) {
  return (
    <div style={{ width: '100%', height: '100%', background: POP_BG, padding: '30px 26px 24px', boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 22 }}>
      <Comp size={172} />
      {/* scale check */}
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 16 }}>
        <Comp size={56} /><Comp size={40} /><Comp size={28} />
      </div>
      <div style={{ textAlign: 'center', marginTop: 'auto' }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: QS.text.value }}>{title}</div>
        <div style={{ fontFamily: QS.mono, fontSize: 10.5, color: QS.text.dim, margin: '3px 0 7px', letterSpacing: '0.06em' }}>{tag}</div>
        <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.55)', lineHeight: 1.45, maxWidth: 240, textWrap: 'pretty' }}>{note}</div>
      </div>
    </div>
  );
}

function SecIcon() {
  return (
    <DCSection id="appicon" title="05 · App icon" subtitle="QuickStatsPanel — glanceable metrics + a slim wide panel + speed. Shown at full + 56 / 40 / 28px.">
      <DCArtboard id="ic-literal" label="A · Literal" width={300} height={420}>
        <IconCase title="Literal" tag="THE STRIP" Comp={IconLiteral}
          note="A miniature of the product itself — a slim hairline-divided strip of live cells. Instantly says what it does." />
      </DCArtboard>
      <DCArtboard id="ic-abstract" label="B · Abstract" width={300} height={420}>
        <IconCase title="Abstract" tag="DATA MOTIF" Comp={IconAbstract}
          note="Bar-graph data rising over a single panel baseline. Reads cleanly down to the smallest sizes." />
      </DCArtboard>
      <DCArtboard id="ic-symbolic" label="C · Symbolic" width={300} height={420}>
        <IconCase title="Symbolic" tag="SUMMON" Comp={IconSymbolic}
          note="A slim panel snapping into place with motion ghosts + a spark — the hotkey-summon gesture, abstracted." />
      </DCArtboard>
    </DCSection>
  );
}

Object.assign(window, { SecIcon });
