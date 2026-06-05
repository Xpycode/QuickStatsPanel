// sec-color.jsx — Prompt 3: at-a-glance color language for stat health.

const RAMP_STEPS = [
  { name: 'Calm', key: 'calm', oklch: 'oklch(.80 .035 225)', role: 'Within normal range. Reads as plain, near-neutral — never demands attention.' },
  { name: 'Caution', key: 'caution', oklch: 'oklch(.835 .13 92)', role: 'Elevated. A first amber nudge; bar only, value still neutral.' },
  { name: 'Warn', key: 'warn', oklch: 'oklch(.74 .165 52)', role: 'Stressed. Bar + value text now tint orange.' },
  { name: 'Critical', key: 'critical', oklch: 'oklch(.66 .205 26)', role: 'Pegged. Bar, value, icon tint + a faint red tile wash.' },
];

function Swatch({ step, i }) {
  const c = QS.ramp[step.key];
  return (
    <div style={{ display: 'flex', gap: 13, alignItems: 'flex-start' }}>
      <span style={{ flex: '0 0 auto', width: 34, height: 34, borderRadius: 8, background: c,
        boxShadow: `0 0 0 1px rgba(255,255,255,0.12), 0 0 18px -2px ${c}` }} />
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{ fontSize: 13.5, fontWeight: 600, color: QS.text.value }}>{i}. {step.name}</span>
          <span style={{ fontFamily: QS.mono, fontSize: 10.5, color: QS.text.dim }}>{step.oklch}</span>
        </div>
        <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.55)', lineHeight: 1.4, marginTop: 3, textWrap: 'pretty' }}>{step.role}</div>
      </div>
    </div>
  );
}

// Build a strip for a stress scenario.
function scenarioStats(cpu, memGB, disk, loadOne, battPct) {
  return {
    cpu: { pct: cpu }, mem: { usedGB: memGB, totalGB: 32 }, disk: { usedPct: disk },
    net: { up: 2, down: 18 }, batt: { pct: battPct }, load: { one: loadOne, cores: 8 },
    uptime: { str: '3d 4h' }, proc: { name: 'Xcode' },
  };
}
function scenarioLevels(s) {
  return {
    cpu: bandLevel('cpu', s.cpu.pct, 0),
    mem: bandLevel('mem', s.mem.usedGB / s.mem.totalGB * 100, 0),
    disk: bandLevel('disk', s.disk.usedPct, 0),
    load: bandLevel('load', s.load.one / s.load.cores, 0),
    batt: bandLevel('batt', s.batt.pct, 0),
  };
}

function ScenarioRow({ title, sub, stats }) {
  const levels = scenarioLevels(stats);
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{ fontSize: 13, fontWeight: 600, color: QS.text.value }}>{title}</span>
        <span style={{ fontFamily: QS.mono, fontSize: 11, color: QS.text.dim }}>{sub}</span>
      </div>
      <HUDStrip stats={stats} levels={levels} order={['cpu', 'mem', 'disk', 'load', 'batt']}
        variant="labelAbove" showGear={false} />
    </div>
  );
}

// Hysteresis band track: colored segments + enter/exit dead-band markers.
function BandTrack({ label, unit, enter, exit, max, inverted = false, ticks }) {
  // build segments in display order (0..max)
  const pos = (v) => `${Math.max(0, Math.min(100, (v / max) * 100))}%`;
  let segs;
  if (!inverted) {
    segs = [
      { from: 0, to: enter[0], lvl: 0 }, { from: enter[0], to: enter[1], lvl: 1 },
      { from: enter[1], to: enter[2], lvl: 2 }, { from: enter[2], to: max, lvl: 3 },
    ];
  } else {
    segs = [
      { from: 0, to: enter[2], lvl: 3 }, { from: enter[2], to: enter[1], lvl: 2 },
      { from: enter[1], to: enter[0], lvl: 1 }, { from: enter[0], to: max, lvl: 0 },
    ];
  }
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ fontSize: 12, fontWeight: 600, color: QS.text.value }}>{label}</span>
        <span style={{ fontFamily: QS.mono, fontSize: 10.5, color: QS.text.dim }}>{unit}</span>
      </div>
      <div style={{ position: 'relative', height: 12, borderRadius: 4, overflow: 'hidden', display: 'flex' }}>
        {segs.map((s, i) => (
          <span key={i} style={{ width: `${((s.to - s.from) / max) * 100}%`,
            background: `color-mix(in oklab, ${QS.levelColor(s.lvl)} 80%, #1a1a1d)` }} />
        ))}
      </div>
      {/* enter (solid ▲) and exit (hollow ▽) markers showing the dead-band */}
      <div style={{ position: 'relative', height: 16 }}>
        {enter.map((e, i) => {
          const x = exit[i];
          return (
            <React.Fragment key={i}>
              <span style={{ position: 'absolute', left: pos(e), top: 0, transform: 'translateX(-50%)',
                fontSize: 8, color: QS.levelColor(i + 1) }}>▲</span>
              <span style={{ position: 'absolute', left: pos(x), top: 0, transform: 'translateX(-50%)',
                fontSize: 8, color: 'rgba(255,255,255,0.4)' }}>▽</span>
              <span style={{ position: 'absolute', left: `calc((${pos(Math.min(e, x))} + ${pos(Math.max(e, x))}) / 2)`,
                top: 9, transform: 'translateX(-50%)', height: 4 }} />
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}

function SecColor() {
  return (
    <DCSection id="color" title="03 · Color language" subtitle="Calm → caution → warn → critical. Tints to signal health without turning into a rainbow or strobing on a boundary.">
      {/* The ramp + where color lives */}
      <DCArtboard id="ramp" label="Semantic ramp" width={400} height={446}>
        <div style={{ width: '100%', height: '100%', background: POP_BG, padding: '26px 24px', boxSizing: 'border-box',
          display: 'flex', flexDirection: 'column', gap: 16 }}>
          {RAMP_STEPS.map((s, i) => <Swatch key={s.key} step={s} i={i} />)}
          <div style={{ height: 1, background: 'rgba(255,255,255,0.08)', margin: '2px 0' }} />
          <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.6)', lineHeight: 1.5, textWrap: 'pretty' }}>
            <b style={{ color: QS.text.value, fontWeight: 600 }}>Where it lives:</b> the thin meter bar is the primary
            carrier (always on). Value text stays neutral until <b style={{ color: QS.levelText(2) }}>warn</b>; the icon
            tints and a faint tile wash appears only at <b style={{ color: QS.levelText(3) }}>critical</b>. One signal at
            a time keeps the panel calm.
          </div>
        </div>
      </DCArtboard>

      {/* Applied across the row at varying stress */}
      <DCArtboard id="applied" label="Applied across the row" width={470} height={446}>
        <div style={{ width: '100%', height: '100%', background: POP_BG, padding: '28px 26px', boxSizing: 'border-box',
          display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
          <ScenarioRow title="Idle" sub="everything within range" stats={scenarioStats(16, 13.5, 64, 0.6, 82)} />
          <ScenarioRow title="Under load" sub="building · sync running" stats={scenarioStats(72, 24, 90, 1.7, 34)} />
          <ScenarioRow title="Critical" sub="thermal · disk full · low batt" stats={scenarioStats(96, 31, 97, 7.8, 8)} />
        </div>
      </DCArtboard>

      {/* Hysteresis bands */}
      <DCArtboard id="hysteresis" label="Hysteresis bands" width={400} height={446}>
        <div style={{ width: '100%', height: '100%', background: POP_BG, padding: '26px 24px', boxSizing: 'border-box',
          display: 'flex', flexDirection: 'column', gap: 15 }}>
          <BandTrack label="CPU %" unit="0–100" enter={[55, 80, 92]} exit={[48, 73, 87]} max={100} />
          <BandTrack label="Memory %" unit="of total" enter={[60, 80, 92]} exit={[53, 73, 87]} max={100} />
          <BandTrack label="Disk full %" unit="0–100" enter={[75, 88, 95]} exit={[70, 84, 92]} max={100} />
          <BandTrack label="Load / core" unit="0–2.0×" enter={[0.7, 1.0, 1.5]} exit={[0.6, 0.9, 1.35]} max={2} />
          <BandTrack label="Battery %" unit="inverted · low = hot" enter={[40, 20, 10]} exit={[45, 25, 13]} max={100} inverted />
          <div style={{ marginTop: 'auto', display: 'flex', gap: 16, alignItems: 'center' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: 'rgba(255,255,255,0.6)' }}>
              <span style={{ color: QS.levelColor(2) }}>▲</span> enter (escalate)</span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: 'rgba(255,255,255,0.6)' }}>
              <span style={{ color: 'rgba(255,255,255,0.5)' }}>▽</span> exit (de-escalate)</span>
          </div>
          <div style={{ fontSize: 11, color: QS.text.dim, lineHeight: 1.4 }}>
            A value must cross the upper ▲ to escalate but fall past the lower ▽ to relax — the gap absorbs jitter so a
            stat parked on a boundary never strobes.
          </div>
        </div>
      </DCArtboard>
    </DCSection>
  );
}

Object.assign(window, { SecColor });
