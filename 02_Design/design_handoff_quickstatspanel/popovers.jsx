// popovers.jsx — detail popover card anchored to a tile (shared pattern).
// Exports: Popover, RestingTile, plus content for disk/batt/load/cpu.

function Caret({ side = 'top', offset = '50%' }) {
  // small pointer triangle; offset = distance from left (top/bottom) edge
  const base = { position: 'absolute', width: 14, height: 14, background: 'rgba(36,36,40,0.94)',
    borderLeft: '1px solid rgba(255,255,255,0.14)', borderTop: '1px solid rgba(255,255,255,0.14)',
    transform: 'rotate(45deg)' };
  if (side === 'top') return <span style={{ ...base, top: -7, left: offset, marginLeft: -7 }} />;
  return <span style={{ ...base, bottom: -7, left: offset, marginLeft: -7, transform: 'rotate(225deg)' }} />;
}

function KV({ k, v, level = 0, mono = true, strong = false }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 14, padding: '3.5px 0' }}>
      <span style={{ fontSize: 12, color: QS.text.label, whiteSpace: 'nowrap' }}>{k}</span>
      <span style={{ fontFamily: mono ? QS.mono : QS.font, fontSize: 12.5, fontWeight: strong ? 600 : 500,
        color: level ? QS.levelText(level) : QS.text.value, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{v}</span>
    </div>
  );
}

function MeterRow({ label, frac, level = 0 }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 5, padding: '2px 0 4px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
        <span style={{ fontSize: 11, color: QS.text.label, letterSpacing: '0.04em', textTransform: 'uppercase' }}>{label}</span>
        <span style={{ fontFamily: QS.mono, fontSize: 11.5, color: QS.levelText(level), fontVariantNumeric: 'tabular-nums' }}>{Math.round(frac * 100)}%</span>
      </div>
      <span style={{ position: 'relative', height: 4, borderRadius: 3, background: 'rgba(255,255,255,0.10)', overflow: 'hidden' }}>
        <span style={{ position: 'absolute', inset: 0, width: `${frac * 100}%`, background: QS.levelColor(level), borderRadius: 3 }} />
      </span>
    </div>
  );
}

function Popover({ icon, title, headline, headLevel = 0, children, footer, width = 224, caret = 'top', caretOffset = '50%' }) {
  return (
    <div style={{ position: 'relative', width, fontFamily: QS.font,
      background: 'rgba(36,36,40,0.92)', backdropFilter: 'blur(30px) saturate(1.6)', WebkitBackdropFilter: 'blur(30px) saturate(1.6)',
      border: '1px solid rgba(255,255,255,0.14)', borderRadius: 12,
      boxShadow: '0 16px 44px rgba(0,0,0,0.5), 0 2px 8px rgba(0,0,0,0.4)', padding: '13px 15px' }}>
      <Caret side={caret} offset={caretOffset} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 4 }}>
        <span style={{ color: QS.text.icon, display: 'flex' }}><Icon name={icon} size={15} /></span>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: QS.text.value, letterSpacing: '0.01em', flex: 1 }}>{title}</span>
        {headline != null && (
          <span style={{ fontFamily: QS.mono, fontSize: 16, fontWeight: 600, color: QS.levelText(headLevel),
            fontVariantNumeric: 'tabular-nums', letterSpacing: '-0.01em' }}>{headline}</span>
        )}
      </div>
      <div style={{ height: 1, background: 'rgba(255,255,255,0.09)', margin: '8px -15px 9px' }} />
      {children}
      {footer && (
        <>
          <div style={{ height: 1, background: 'rgba(255,255,255,0.09)', margin: '9px -15px 8px' }} />
          <div style={{ fontSize: 11, color: QS.text.dim, lineHeight: 1.4 }}>{footer}</div>
        </>
      )}
    </div>
  );
}

// Resting tile rendered standalone (in its own mini panel) for the "before" state.
function RestingTile({ tileProps, variant = 'labelAbove', height = 54 }) {
  return (
    <Panel height={height}>
      <Tile {...tileProps} variant={variant} />
    </Panel>
  );
}

// ── Content builders ───────────────────────────────────────────────────────
function DiskPopover() {
  return (
    <Popover icon="disk" title="Macintosh HD" headline="64%" headLevel={0} width={236}>
      <MeterRow label="Used" frac={0.64} level={0} />
      <div style={{ marginTop: 4 }}>
        <KV k="Used" v="297 GB" />
        <KV k="Free" v="163 GB" />
        <KV k="Total" v="460 GB" strong />
      </div>
      <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', margin: '8px -15px' }} />
      <KV k="Read" v="4.2 MB/s" />
      <KV k="Write" v="1.1 MB/s" />
    </Popover>
  );
}

function BattPopover() {
  return (
    <Popover icon="battery" title="Battery" headline="82%" headLevel={0} width={224}>
      <MeterRow label="Charge" frac={0.82} level={0} />
      <div style={{ marginTop: 4 }}>
        <KV k="State" v="On battery" />
        <KV k="Time remaining" v="3:34" strong />
        <KV k="Condition" v="Normal" />
        <KV k="Cycles" v="218" />
      </div>
    </Popover>
  );
}

function LoadPopover() {
  return (
    <Popover icon="load" title="Load average" headline="1.42" headLevel={1} width={224}>
      <KV k="1 min" v="1.42" level={1} strong />
      <KV k="5 min" v="1.18" />
      <KV k="15 min" v="0.96" />
      <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', margin: '8px -15px' }} />
      <KV k="Active cores" v="8" />
      <div style={{ marginTop: 6 }}>
        <MeterRow label="Load / core" frac={1.42 / 8} level={1} />
      </div>
    </Popover>
  );
}

function CpuPopover() {
  return (
    <Popover icon="cpu" title="Processor" headline="23%" headLevel={0} width={224}>
      <MeterRow label="Total" frac={0.23} level={0} />
      <div style={{ marginTop: 4 }}>
        <KV k="User" v="14%" />
        <KV k="System" v="9%" />
        <KV k="Idle" v="77%" />
      </div>
      <div style={{ height: 1, background: 'rgba(255,255,255,0.07)', margin: '8px -15px' }} />
      <KV k="Top process" v="Xcode · 42%" />
    </Popover>
  );
}

Object.assign(window, { Popover, Caret, KV, MeterRow, RestingTile, DiskPopover, BattPopover, LoadPopover, CpuPopover });
