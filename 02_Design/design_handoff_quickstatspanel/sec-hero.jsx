// sec-hero.jsx — Prompt 1: the core HUD strip (hero) + 3 tile-layout variations.

const DEFAULT_ORDER = ['cpu', 'mem', 'disk', 'net', 'batt', 'load', 'uptime', 'proc'];

// A frozen snapshot for the static variation cards (so they read clean).
const SNAP = {
  cpu: { pct: 23 }, mem: { usedGB: 16.9, totalGB: 32 }, disk: { usedPct: 64 },
  net: { up: 2.4, down: 18.6 }, batt: { pct: 82 }, load: { one: 1.42, cores: 8 },
  uptime: { str: '3d 4h' }, proc: { name: 'Xcode' },
};
const SNAP_LEVELS = { cpu: 0, mem: 0, disk: 0, load: 1, batt: 0 };

// label for the floating-panel annotations
function HeroCaption({ children }) {
  return <div style={{ marginTop: 22, fontFamily: QS.mono, fontSize: 12, color: 'rgba(255,255,255,0.5)',
    letterSpacing: '0.02em', textAlign: 'center' }}>{children}</div>;
}

function HeroLive({ onGear, onTile, active }) {
  const { stats, levels } = useLiveStats(1000);
  return <HUDStrip stats={stats} levels={levels} order={DEFAULT_ORDER}
    variant="labelAbove" onGear={onGear} onTile={onTile} active={active} />;
}

function SecHero({ onGear, onTile, active }) {
  const variants = [
    { id: 'v-labelabove', label: 'A · Label-above-value', variant: 'labelAbove', height: 54,
      note: 'Default. Micro-label + inline icon on top, monospaced value below. Reads top-down, tightest height.' },
    { id: 'v-iconleft', label: 'B · Icon-left / value-right', variant: 'iconLeft', height: 56,
      note: 'Icon anchors the left edge; label + value stack to its right. Most legible at a glance, widest tiles.' },
    { id: 'v-stacked', label: 'C · Fully stacked', variant: 'stacked', height: 64,
      note: 'Icon → label → value, centered. Most "instrument" feel; needs a taller strip.' },
  ];
  const subset = ['cpu', 'mem', 'disk', 'batt'];

  return (
    <DCSection id="hero" title="01 · The HUD strip" subtitle="Floating macOS panel — 36pt tall, 12pt radius, content-hugging width. Live & clickable.">
      {/* Hero: live strip over desktop */}
      <DCArtboard id="hero-live" label="Hero — live over desktop" width={1000} height={400}
        style={{ background: QS.wallpaper }}>
        <div style={{ position: 'relative', width: '100%', height: '100%', display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
          <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(80% 60% at 50% 120%, rgba(0,0,0,0.35), transparent)' }} />
          <div style={{ position: 'relative' }}>
            <HeroLive onGear={onGear} onTile={onTile} active={active} />
            <HeroCaption>36pt tall · 12pt corner · hairline dividers · click any tile</HeroCaption>
          </div>
        </div>
      </DCArtboard>

      {/* Tile-layout variations */}
      {variants.map((v) => (
        <DCArtboard key={v.id} id={v.id} label={v.label} width={430} height={400}
          style={{ background: QS.wallpaperWarm }}>
          <div style={{ width: '100%', height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', gap: 26, padding: 28, boxSizing: 'border-box' }}>
            <HUDStrip stats={SNAP} levels={SNAP_LEVELS} order={subset} variant={v.variant} height={v.height} showGear={false} />
            <div style={{ fontFamily: QS.font, fontSize: 12.5, lineHeight: 1.5, color: 'rgba(255,255,255,0.66)',
              textAlign: 'center', maxWidth: 320, textWrap: 'pretty' }}>{v.note}</div>
          </div>
        </DCArtboard>
      ))}
    </DCSection>
  );
}

Object.assign(window, { SecHero, DEFAULT_ORDER, SNAP, SNAP_LEVELS });
