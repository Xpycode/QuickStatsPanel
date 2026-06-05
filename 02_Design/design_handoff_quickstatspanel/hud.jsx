// hud.jsx — the floating HUD strip: tiles, dividers, live-stat simulation,
// and the hysteresis-banded health-level logic. Exports HUDStrip, Tile,
// useLiveStats, and level helpers to window.

// ── Health bands (enter/exit pairs give hysteresis so a value sitting on a
//    boundary doesn't strobe). Each: [cautionEnter, warnEnter, critEnter] and
//    matching exit thresholds one band lower. `inverted` flips direction
//    (battery: LOW is hot). ─────────────────────────────────────────────────
const BANDS = {
  cpu:   { enter: [55, 80, 92], exit: [48, 73, 87] },
  mem:   { enter: [60, 80, 92], exit: [53, 73, 87] },
  disk:  { enter: [75, 88, 95], exit: [70, 84, 92] },
  load:  { enter: [0.7, 1.0, 1.5], exit: [0.6, 0.9, 1.35] }, // per active core
  batt:  { enter: [40, 20, 10], exit: [45, 25, 13], inverted: true },
};

// Pure banding with hysteresis. prev = last level (0..3).
function bandLevel(key, value, prev = 0) {
  const b = BANDS[key];
  if (!b) return 0;
  let lvl = prev;
  if (b.inverted) {
    // lower = worse. enter thresholds are descending.
    if (value <= b.enter[2]) lvl = 3;
    else if (value <= b.enter[1]) lvl = Math.max(prev >= 3 && value < b.exit[2] ? 3 : 2, prev === 3 && value < b.exit[2] ? 3 : 2);
    else if (value <= b.enter[0]) lvl = 1;
    else lvl = 0;
    // simple hysteresis on the way up (recovering)
    if (prev === 3 && value < b.exit[2]) lvl = 3;
    else if (prev >= 2 && value < b.exit[1]) lvl = Math.max(lvl, 2);
    else if (prev >= 1 && value < b.exit[0]) lvl = Math.max(lvl, 1);
  } else {
    if (value >= b.enter[2]) lvl = 3;
    else if (value >= b.enter[1]) lvl = 2;
    else if (value >= b.enter[0]) lvl = 1;
    else lvl = 0;
    // don't drop a band until we cross the lower exit threshold
    if (prev === 3 && value > b.exit[2]) lvl = 3;
    else if (prev >= 2 && value > b.exit[1]) lvl = Math.max(lvl, 2);
    else if (prev >= 1 && value > b.exit[0]) lvl = Math.max(lvl, 1);
  }
  return lvl;
}

// meter fill (0..1) for a stat's bar
function meterFor(key, value) {
  if (key === 'batt') return Math.max(0, Math.min(1, value / 100));
  if (key === 'load') return Math.max(0, Math.min(1, value / 2));
  return Math.max(0, Math.min(1, value / 100));
}

// ── One tile. variant: 'labelAbove' | 'iconLeft' | 'stacked' ───────────────
function Tile({ icon, label, value, unit, sub, level = 0, meter = null, variant = 'labelAbove',
                width, active = false, onClick, dim = false }) {
  const valColor = QS.levelText(level);
  const barColor = QS.levelColor(level);
  const showBar = meter != null;
  const wash = level >= 3 ? `color-mix(in oklab, ${QS.levelColor(3)} 12%, transparent)`
             : level === 2 ? `color-mix(in oklab, ${QS.levelColor(2)} 7%, transparent)` : 'transparent';

  const valEl = (
    <span style={{ fontFamily: QS.mono, fontWeight: 600, color: dim ? QS.text.dim : valColor,
      fontVariantNumeric: 'tabular-nums', letterSpacing: '-0.01em', whiteSpace: 'nowrap', lineHeight: 1 }}>
      {value}{unit && <span style={{ opacity: 0.5, fontWeight: 500, marginLeft: 1 }}>{unit}</span>}
    </span>
  );
  const labelEl = (
    <span style={{ fontSize: 9.5, fontWeight: 600, letterSpacing: '0.07em', textTransform: 'uppercase',
      color: QS.text.label, lineHeight: 1, whiteSpace: 'nowrap' }}>{label}</span>
  );
  const iconEl = icon && (
    <span style={{ color: level >= 3 ? barColor : QS.text.icon, display: 'flex' }}>
      <Icon name={icon} size={variant === 'iconLeft' ? 17 : 14} />
    </span>
  );

  let inner;
  if (variant === 'iconLeft') {
    inner = (
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {iconEl}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 3, alignItems: 'flex-start' }}>
          {labelEl}
          <span style={{ fontSize: 17 }}>{valEl}</span>
        </div>
      </div>
    );
  } else if (variant === 'stacked') {
    inner = (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }}>
        {iconEl}
        {labelEl}
        <span style={{ fontSize: 16 }}>{valEl}</span>
      </div>
    );
  } else { // labelAbove (default)
    inner = (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-start' }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>{iconEl}{labelEl}</span>
        <span style={{ fontSize: 17, display: 'flex', alignItems: 'baseline', gap: 3 }}>
          {valEl}
          {sub && <span style={{ fontFamily: QS.mono, fontSize: 11, color: QS.text.label, fontVariantNumeric: 'tabular-nums' }}>{sub}</span>}
        </span>
      </div>
    );
  }

  return (
    <button
      onClick={onClick}
      style={{
        position: 'relative', appearance: 'none', border: 'none', background: active ? 'rgba(255,255,255,0.08)' : wash,
        cursor: onClick ? 'pointer' : 'default', font: 'inherit', textAlign: variant === 'stacked' ? 'center' : 'left',
        padding: variant === 'stacked' ? '8px 14px' : '0 15px', height: '100%', minWidth: width,
        display: 'flex', alignItems: 'center', justifyContent: variant === 'stacked' ? 'center' : 'flex-start',
        transition: 'background 0.14s',
      }}>
      {inner}
      {showBar && (
        <span style={{ position: 'absolute', left: 15, right: 15, bottom: 7, height: 2, borderRadius: 2,
          background: 'rgba(255,255,255,0.10)', overflow: 'hidden' }}>
          <span style={{ position: 'absolute', inset: 0, width: `${meter * 100}%`, background: barColor,
            borderRadius: 2, transition: 'width 0.5s ease, background 0.4s' }} />
        </span>
      )}
    </button>
  );
}

function Divider() {
  return <span style={{ alignSelf: 'stretch', width: 1, background: QS.panel.divider, margin: '9px 0' }} />;
}

// The panel shell — translucent vibrancy material with border + shadow.
function Panel({ children, height = QS.panel.height, style }) {
  return (
    <div style={{
      height, display: 'inline-flex', alignItems: 'stretch',
      background: QS.panel.bg, backdropFilter: 'blur(28px) saturate(1.7)', WebkitBackdropFilter: 'blur(28px) saturate(1.7)',
      borderRadius: QS.panel.radius, border: `1px solid ${QS.panel.border}`,
      boxShadow: QS.panel.shadow, overflow: 'hidden', ...style,
    }}>{children}</div>
  );
}

// Trailing gear tile.
function GearTile({ onClick, active }) {
  return (
    <button onClick={onClick} title="Settings" style={{
      appearance: 'none', border: 'none', background: active ? 'rgba(255,255,255,0.08)' : 'transparent',
      cursor: 'pointer', color: QS.text.icon, padding: '0 13px', height: '100%', display: 'flex', alignItems: 'center',
      transition: 'background 0.14s, color 0.14s',
    }}
      onMouseEnter={(e) => (e.currentTarget.style.color = QS.text.value)}
      onMouseLeave={(e) => (e.currentTarget.style.color = QS.text.icon)}>
      <Icon name="gear" size={16} />
    </button>
  );
}

// ── Format helpers ─────────────────────────────────────────────────────────
const fmt = {
  pct: (v) => String(Math.round(v)),
  gb: (v) => v.toFixed(1),
  rate: (v) => (v >= 100 ? Math.round(v) : v.toFixed(1)),
  load: (v) => v.toFixed(2),
};

// Build the ordered tile list from a stats object + level memory.
function tilesFromStats(stats, levels) {
  const cores = stats.load.cores;
  return {
    cpu:  { icon: 'cpu', label: 'CPU', value: fmt.pct(stats.cpu.pct), unit: '%', level: levels.cpu, meter: meterFor('cpu', stats.cpu.pct), width: 64 },
    mem:  { icon: 'memory', label: 'MEM', value: fmt.gb(stats.mem.usedGB), unit: 'GB', level: levels.mem, meter: meterFor('mem', stats.mem.usedGB / stats.mem.totalGB * 100), width: 78 },
    disk: { icon: 'disk', label: 'DISK', value: fmt.pct(stats.disk.usedPct), unit: '%', level: levels.disk, meter: meterFor('disk', stats.disk.usedPct), width: 64 },
    net:  { icon: 'network', label: 'NET', value: `↓${fmt.rate(stats.net.down)}`, sub: `↑${fmt.rate(stats.net.up)}`, level: 0, width: 108 },
    batt: { icon: 'battery', label: 'BATT', value: fmt.pct(stats.batt.pct), unit: '%', level: levels.batt, meter: meterFor('batt', stats.batt.pct), width: 64 },
    load: { icon: 'load', label: 'LOAD', value: fmt.load(stats.load.one), level: levels.load, meter: meterFor('load', stats.load.one / cores), width: 64 },
    uptime: { icon: 'uptime', label: 'UPTIME', value: stats.uptime.str, level: 0, width: 76 },
    proc: { icon: 'process', label: 'TOP PROC', value: stats.proc.name, level: 0, width: 110 },
  };
}

// HUDStrip — renders tiles in `order`, with dividers + trailing gear.
function HUDStrip({ stats, levels, order, variant = 'labelAbove', height = QS.panel.height,
                    onTile, onGear, active = null, showGear = true }) {
  const t = tilesFromStats(stats, levels);
  const items = order.filter((k) => t[k]);
  return (
    <Panel height={height}>
      {items.map((k, i) => (
        <React.Fragment key={k}>
          {i > 0 && <Divider />}
          <Tile {...t[k]} variant={variant} active={active === k} onClick={onTile ? () => onTile(k) : undefined} />
        </React.Fragment>
      ))}
      {showGear && <><Divider /><GearTile onClick={onGear} active={active === 'gear'} /></>}
    </Panel>
  );
}

// ── Live-stat simulation. Smooth random walks; CPU/net occasionally spike.
function useLiveStats(intervalMs = 1000) {
  const [stats, setStats] = React.useState(() => ({
    cpu: { pct: 18 },
    mem: { usedGB: 16.9, totalGB: 32 },
    disk: { usedPct: 64, readMB: 4.2, writeMB: 1.1, usedGB: 297, freeGB: 163, totalGB: 460 },
    net: { up: 2.4, down: 18.6 },
    batt: { pct: 82, charging: false, mins: 214 },
    load: { one: 1.42, five: 1.18, fifteen: 0.96, cores: 8 },
    uptime: { str: '3d 4h', secs: 273840 },
    proc: { name: 'Xcode', memGB: 3.8, cpu: 42 },
  }));
  const levelsRef = React.useRef({ cpu: 0, mem: 0, disk: 0, load: 1, batt: 0 });
  const [levels, setLevels] = React.useState(levelsRef.current);

  React.useEffect(() => {
    const walk = (v, lo, hi, step) => Math.max(lo, Math.min(hi, v + (Math.random() - 0.5) * step));
    const id = setInterval(() => {
      setStats((s) => {
        const spike = Math.random() < 0.12;
        const cpu = walk(s.cpu.pct, 3, spike ? 98 : 70, spike ? 60 : 16);
        const mem = walk(s.mem.usedGB, 10, 30, 0.6);
        const load = walk(s.load.one, 0.2, 9, 0.8);
        const next = {
          ...s,
          cpu: { pct: cpu },
          mem: { ...s.mem, usedGB: mem },
          disk: { ...s.disk, usedPct: walk(s.disk.usedPct, 60, 70, 0.4), readMB: walk(s.disk.readMB, 0, 220, 40), writeMB: walk(s.disk.writeMB, 0, 90, 20) },
          net: { up: walk(s.net.up, 0, 60, 12), down: walk(s.net.down, 0, 240, 40) },
          load: { ...s.load, one: load, five: walk(s.load.five, 0.2, 6, 0.3), fifteen: walk(s.load.fifteen, 0.2, 5, 0.15) },
        };
        const L = levelsRef.current;
        const nl = {
          cpu: bandLevel('cpu', cpu, L.cpu),
          mem: bandLevel('mem', mem / next.mem.totalGB * 100, L.mem),
          disk: bandLevel('disk', next.disk.usedPct, L.disk),
          load: bandLevel('load', load / next.load.cores, L.load),
          batt: bandLevel('batt', s.batt.pct, L.batt),
        };
        levelsRef.current = nl;
        setLevels(nl);
        return next;
      });
    }, intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);

  return { stats, levels };
}

Object.assign(window, { Tile, Divider, Panel, GearTile, HUDStrip, useLiveStats, bandLevel, meterFor, tilesFromStats, fmt });
