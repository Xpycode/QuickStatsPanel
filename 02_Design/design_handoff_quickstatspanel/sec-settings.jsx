// sec-settings.jsx — Prompt 4: compact dark macOS Settings window.
// No Dock icon / no menu-bar item — opens from the gear tile in the panel.

const STAT_DEFS = {
  cpu: { icon: 'cpu', name: 'CPU' },
  mem: { icon: 'memory', name: 'Memory' },
  disk: { icon: 'disk', name: 'Disk' },
  net: { icon: 'network', name: 'Network' },
  batt: { icon: 'battery', name: 'Battery' },
  load: { icon: 'load', name: 'Load average' },
  uptime: { icon: 'uptime', name: 'Uptime' },
  proc: { icon: 'process', name: 'Top Process' },
};

function Switch({ on, onChange }) {
  return (
    <button onClick={() => onChange(!on)} role="switch" aria-checked={on} style={{
      width: 38, height: 22, borderRadius: 11, border: 'none', cursor: 'pointer', padding: 2, flex: '0 0 auto',
      background: on ? QS.accent : 'rgba(255,255,255,0.16)', transition: 'background 0.18s', position: 'relative',
    }}>
      <span style={{ display: 'block', width: 18, height: 18, borderRadius: 9, background: '#fff',
        boxShadow: '0 1px 2px rgba(0,0,0,0.35)', transform: on ? 'translateX(16px)' : 'translateX(0)',
        transition: 'transform 0.18s cubic-bezier(.3,.7,.3,1)' }} />
    </button>
  );
}

// macOS-style grouped card
function Group({ label, children, style }) {
  return (
    <div style={{ ...style }}>
      {label && <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase',
        color: QS.text.label, margin: '0 0 7px 4px' }}>{label}</div>}
      <div style={{ background: 'rgba(255,255,255,0.045)', border: '1px solid rgba(255,255,255,0.07)',
        borderRadius: 9, overflow: 'hidden' }}>{children}</div>
    </div>
  );
}

function Row({ children, last, style }) {
  return <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '0 12px', minHeight: 38,
    borderBottom: last ? 'none' : '1px solid rgba(255,255,255,0.06)', ...style }}>{children}</div>;
}

// Drag-reorderable + toggleable stat list
function StatList() {
  const [order, setOrder] = React.useState(['cpu', 'mem', 'disk', 'net', 'batt', 'load', 'uptime', 'proc']);
  const [enabled, setEnabled] = React.useState({ cpu: true, mem: true, disk: true, net: true, batt: false, load: true, uptime: true, proc: true });
  const [dragId, setDragId] = React.useState(null);
  const listRef = React.useRef(null);
  const ROW = 38;

  const onGripDown = (e, id) => {
    e.preventDefault();
    setDragId(id);
    const startY = e.clientY;
    const startOrder = order.slice();
    const startIdx = startOrder.indexOf(id);
    const move = (ev) => {
      const dy = ev.clientY - startY;
      let target = Math.max(0, Math.min(startOrder.length - 1, startIdx + Math.round(dy / ROW)));
      if (target !== order.indexOf(id)) {
        const next = startOrder.filter((k) => k !== id);
        next.splice(target, 0, id);
        setOrder(next);
      }
    };
    const up = () => { setDragId(null); document.removeEventListener('pointermove', move); document.removeEventListener('pointerup', up); };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
  };

  return (
    <Group label="Stats" >
      <div ref={listRef}>
        {order.map((id, i) => {
          const d = STAT_DEFS[id];
          const dragging = dragId === id;
          return (
            <Row key={id} last={i === order.length - 1}
              style={{ background: dragging ? 'rgba(255,255,255,0.07)' : 'transparent',
                position: 'relative', zIndex: dragging ? 2 : 1, transition: 'background 0.12s' }}>
              <span onPointerDown={(e) => onGripDown(e, id)} title="Drag to reorder"
                style={{ cursor: 'grab', color: QS.text.dim, display: 'flex', padding: '4px 2px', touchAction: 'none' }}>
                <svg width="9" height="14" viewBox="0 0 9 14" fill="currentColor"><circle cx="2" cy="2.5" r="1"/><circle cx="7" cy="2.5" r="1"/><circle cx="2" cy="7" r="1"/><circle cx="7" cy="7" r="1"/><circle cx="2" cy="11.5" r="1"/><circle cx="7" cy="11.5" r="1"/></svg>
              </span>
              <span style={{ color: enabled[id] ? QS.text.icon : QS.text.dim, display: 'flex' }}><Icon name={d.icon} size={15} /></span>
              <span style={{ flex: 1, fontSize: 13, color: enabled[id] ? QS.text.value : QS.text.dim }}>{d.name}</span>
              {id === 'batt' && <span style={{ fontSize: 10.5, color: QS.text.dim, marginRight: 2 }}>auto-hidden · desktop</span>}
              <Switch on={enabled[id]} onChange={(v) => setEnabled((e) => ({ ...e, [id]: v }))} />
            </Row>
          );
        })}
      </div>
    </Group>
  );
}

function SliderRow({ label, min, max, step, value, onChange, format }) {
  return (
    <Row last style={{ flexDirection: 'column', alignItems: 'stretch', padding: '11px 12px', gap: 8 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ fontSize: 13, color: QS.text.value }}>{label}</span>
        <span style={{ fontFamily: QS.mono, fontSize: 12.5, color: QS.text.value, fontVariantNumeric: 'tabular-nums' }}>{format(value)}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{ width: '100%', accentColor: QS.accent, height: 4, cursor: 'pointer' }} />
    </Row>
  );
}

// Anchor picker — 4 little "screen" diagrams
function AnchorGlyph({ kind, active }) {
  const dot = (style) => <span style={{ position: 'absolute', width: 6, height: 6, borderRadius: 2,
    background: active ? '#fff' : QS.text.label, ...style }} />;
  const screenStyle = { position: 'relative', width: 44, height: 30, borderRadius: 4,
    border: `1.5px solid ${active ? QS.accent : 'rgba(255,255,255,0.2)'}`, background: active ? 'rgba(255,255,255,0.06)' : 'transparent' };
  let mark;
  if (kind === 'cursor') mark = (<>
    {dot({ top: 11, left: 13 })}
    <svg width="9" height="9" viewBox="0 0 9 9" style={{ position: 'absolute', top: 9, left: 20, color: active ? '#fff' : QS.text.label }} fill="currentColor"><path d="M0 0l9 3.5-3.6 1.2L4 9z"/></svg>
  </>);
  if (kind === 'center') mark = dot({ top: 12, left: '50%', marginLeft: -3 });
  if (kind === 'top') mark = <span style={{ position: 'absolute', top: 4, left: 9, right: 9, height: 5, borderRadius: 2, background: active ? '#fff' : QS.text.label }} />;
  if (kind === 'bottom') mark = <span style={{ position: 'absolute', bottom: 4, left: 9, right: 9, height: 5, borderRadius: 2, background: active ? '#fff' : QS.text.label }} />;
  return <span style={screenStyle}>{mark}</span>;
}

function AnchorPicker() {
  const opts = [{ k: 'cursor', n: 'Near cursor' }, { k: 'center', n: 'Screen center' }, { k: 'top', n: 'Top center' }, { k: 'bottom', n: 'Bottom center' }];
  const [sel, setSel] = React.useState('cursor');
  return (
    <Group label="Panel anchor">
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 0 }}>
        {opts.map((o, i) => (
          <button key={o.k} onClick={() => setSel(o.k)} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, padding: '14px 6px', cursor: 'pointer',
            border: 'none', background: sel === o.k ? 'rgba(255,255,255,0.05)' : 'transparent', font: 'inherit',
            borderRight: i % 2 === 0 ? '1px solid rgba(255,255,255,0.06)' : 'none',
            borderBottom: i < 2 ? '1px solid rgba(255,255,255,0.06)' : 'none' }}>
            <AnchorGlyph kind={o.k} active={sel === o.k} />
            <span style={{ fontSize: 12, color: sel === o.k ? QS.text.value : QS.text.label }}>{o.n}</span>
          </button>
        ))}
      </div>
    </Group>
  );
}

function Keycap({ children, wide }) {
  return <span style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
    minWidth: wide ? 'auto' : 24, height: 24, padding: wide ? '0 9px' : '0 4px', borderRadius: 6,
    background: 'rgba(255,255,255,0.10)', border: '1px solid rgba(255,255,255,0.14)',
    boxShadow: '0 1px 0 rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.08)',
    fontFamily: QS.font, fontSize: 13, color: QS.text.value, fontWeight: 500 }}>{children}</span>;
}

function HotkeyField({ recording, onToggle }) {
  return (
    <button onClick={onToggle} style={{
      width: '100%', display: 'flex', alignItems: 'center', gap: 7, minHeight: 38, padding: '7px 11px',
      border: `1px solid ${recording ? QS.accent : 'rgba(255,255,255,0.12)'}`, borderRadius: 8, cursor: 'pointer',
      background: recording ? 'color-mix(in oklab, ' + QS.accent + ' 14%, transparent)' : 'rgba(255,255,255,0.04)',
      boxShadow: recording ? `0 0 0 3px color-mix(in oklab, ${QS.accent} 22%, transparent)` : 'none',
      transition: 'box-shadow .15s, border-color .15s, background .15s', font: 'inherit', justifyContent: recording ? 'flex-start' : 'space-between' }}>
      {recording ? (
        <span style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
          <span className="qs-rec-dot" style={{ width: 9, height: 9, borderRadius: 5, background: QS.levelColor(3) }} />
          <span style={{ fontSize: 13, color: QS.text.value }}>Press your shortcut now…</span>
        </span>
      ) : (
        <>
          <span style={{ display: 'flex', gap: 4 }}>
            <Keycap>⌃</Keycap><Keycap>⌥</Keycap><Keycap>⌘</Keycap><Keycap>Q</Keycap>
          </span>
          <span style={{ fontSize: 12, color: QS.text.label }}>Click to change</span>
        </>
      )}
    </button>
  );
}

function FooterBtn({ children, danger, onClick }) {
  return <button onClick={onClick} style={{ flex: 1, height: 32, borderRadius: 7, cursor: 'pointer', font: 'inherit',
    fontSize: 13, fontWeight: 500, color: danger ? QS.levelText(3) : QS.text.value,
    background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.10)', transition: 'background .12s' }}
    onMouseEnter={(e) => (e.currentTarget.style.background = 'rgba(255,255,255,0.11)')}
    onMouseLeave={(e) => (e.currentTarget.style.background = 'rgba(255,255,255,0.06)')}>{children}</button>;
}

function SettingsWindow({ recording, setRecording, interval, setInterval, stripH, setStripH }) {
  return (
    <div style={{ width: '100%', height: '100%', background: '#262629', display: 'flex', flexDirection: 'column',
      fontFamily: QS.font, overflow: 'hidden' }}>
      {/* title bar */}
      <div style={{ height: 40, flex: '0 0 auto', display: 'flex', alignItems: 'center', padding: '0 14px',
        borderBottom: '1px solid rgba(255,255,255,0.07)', position: 'relative' }}>
        <span style={{ display: 'flex', gap: 8 }}>
          <span style={{ width: 12, height: 12, borderRadius: 6, background: '#ff5f57' }} />
          <span style={{ width: 12, height: 12, borderRadius: 6, background: '#febc2e' }} />
          <span style={{ width: 12, height: 12, borderRadius: 6, background: '#28c840' }} />
        </span>
        <span style={{ position: 'absolute', left: 0, right: 0, textAlign: 'center', fontSize: 13, fontWeight: 600,
          color: QS.text.value, pointerEvents: 'none' }}>QuickStats Settings</span>
      </div>
      {/* body */}
      <div style={{ flex: 1, padding: 16, display: 'flex', flexDirection: 'column', gap: 16, overflow: 'hidden' }}>
        <StatList />
        <Group>
          <SliderRow label="Sampling interval" min={0.25} max={5} step={0.25} value={interval} onChange={setInterval}
            format={(v) => `${v.toFixed(2)}s`} />
        </Group>
        <AnchorPicker />
        <Group>
          <SliderRow label="Strip height" min={22} max={44} step={1} value={stripH} onChange={setStripH}
            format={(v) => `${v}pt`} />
        </Group>
        <Group label="Global hotkey">
          <div style={{ padding: 11 }}>
            <HotkeyField recording={recording} onToggle={() => setRecording((r) => !r)} />
          </div>
        </Group>
        <div style={{ display: 'flex', gap: 10, marginTop: 'auto' }}>
          <FooterBtn>Reset…</FooterBtn>
          <FooterBtn danger>Quit QuickStats</FooterBtn>
        </div>
      </div>
    </div>
  );
}

function SettingsLive() {
  const [recording, setRecording] = React.useState(false);
  const [interval, setIntervalV] = React.useState(1);
  const [stripH, setStripH] = React.useState(36);
  return <SettingsWindow recording={recording} setRecording={setRecording}
    interval={interval} setInterval={setIntervalV} stripH={stripH} setStripH={setStripH} />;
}

function SecSettings() {
  return (
    <DCSection id="settings" title="04 · Settings window" subtitle="Opens from the gear tile — no Dock icon, no menu-bar item. Live: toggle, drag-reorder, drag sliders.">
      <DCArtboard id="settings-window" label="Settings — interactive" width={420} height={720}
        style={{ borderRadius: 10, boxShadow: '0 24px 70px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.08)' }}>
        <SettingsLive />
      </DCArtboard>

      {/* Hotkey recorder — both states */}
      <DCArtboard id="hotkey-states" label="Hotkey recorder — two states" width={360} height={720}>
        <div style={{ width: '100%', height: '100%', background: POP_BG, padding: 26, boxSizing: 'border-box',
          display: 'flex', flexDirection: 'column', gap: 30, justifyContent: 'center' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <span style={{ fontFamily: QS.mono, fontSize: 10.5, letterSpacing: '0.08em', color: QS.text.dim }}>RESTING</span>
            <HotkeyField recording={false} onToggle={() => {}} />
            <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.5)', lineHeight: 1.45 }}>
              Shows the current combo as keycaps. The whole field is the hit target.</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <span style={{ fontFamily: QS.mono, fontSize: 10.5, letterSpacing: '0.08em', color: QS.text.dim }}>RECORDING</span>
            <HotkeyField recording={true} onToggle={() => {}} />
            <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.5)', lineHeight: 1.45 }}>
              Accent ring + pulsing dot. The next modifier+key chord is captured; Esc cancels.</span>
          </div>
        </div>
      </DCArtboard>
    </DCSection>
  );
}

Object.assign(window, { SecSettings, SettingsWindow, HotkeyField, Switch });
